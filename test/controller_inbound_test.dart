// Unit tests for HuddleController's inbound-frame handling — the guard
// conditions and bookkeeping the happy-path end-to-end test doesn't pin down
// (rejecting unpaired senders, de-duplication, timestamp fallback, malformed
// photos, unpair from a stranger, unread tracking).
//
// Frames are delivered through a real loopback TransportService acting as the
// remote peer, so the controller's own transport decodes them exactly as it
// would in production. The received-file folder is pointed at a temp directory
// so photo saving needs no path_provider plugin.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/models/chat_message.dart';
import 'package:huddle/models/peer.dart';
import 'package:huddle/services/protocol.dart';
import 'package:huddle/services/storage_service.dart';
import 'package:huddle/services/transport_service.dart';
import 'package:huddle/state/huddle_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory mediaDir;
  final controllers = <HuddleController>[];
  final peers = <TransportService>[];

  setUp(() {
    mediaDir = Directory.systemTemp.createTempSync('huddle_inbound_');
  });

  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    for (final p in peers) {
      await p.dispose();
    }
    controllers.clear();
    peers.clear();
    if (mediaDir.existsSync()) mediaDir.deleteSync(recursive: true);
  });

  /// A controller whose received-file folder is [mediaDir] and that is already
  /// paired with each id in [pairedWith] (seeded straight into storage).
  Future<HuddleController> startController(
      {List<String> pairedWith = const []}) async {
    SharedPreferences.setMockInitialValues({'huddle.media.dir': mediaDir.path});
    final prefs = await SharedPreferences.getInstance();
    if (pairedWith.isNotEmpty) {
      await StorageService(prefs).savePeers([
        for (final id in pairedWith)
          Peer(
              id: id,
              name: id,
              platform: 'android',
              pairedAt: DateTime(2026)),
      ]);
    }
    final c = HuddleController();
    await c.init();
    controllers.add(c);
    expect(c.tcpPort, greaterThan(0),
        reason: 'transport must be listening for the inbound tests to run');
    return c;
  }

  /// A loopback transport standing in for a remote peer with [id].
  Future<TransportService> peer(String id, [String name = 'Phone']) async {
    final p = TransportService(id: id, name: name, platform: 'android');
    await p.start();
    peers.add(p);
    return p;
  }

  group('text frames', () {
    test('text from an unpaired sender is ignored (but the device is seen)',
        () async {
      final c = await startController(); // no peers
      final stranger = await peer('stranger', 'Nope');

      await stranger
          .send('127.0.0.1', c.tcpPort, FrameType.text, {'mid': 'm1', 'text': 'hi'});

      // Once the device shows up the frame has been processed end to end…
      await _waitFor(() => c.deviceFor('stranger') != null);
      // …yet without an agreement nothing was stored.
      expect(c.conversation('stranger'), isEmpty);
      expect(c.unreadFor('stranger'), 0);
    });

    test('text from a paired peer is stored, not-mine, and bumps unread',
        () async {
      final c = await startController(pairedWith: ['p1']);
      final p1 = await peer('p1');

      await p1.send('127.0.0.1', c.tcpPort, FrameType.text,
          {'mid': 'm1', 'text': 'hello', 'ts': 1000});

      await _waitFor(() => c.conversation('p1').isNotEmpty);
      final msg = c.conversation('p1').single;
      expect(msg.text, 'hello');
      expect(msg.mine, isFalse);
      expect(msg.kind, MessageKind.text);
      expect(msg.sentAt.millisecondsSinceEpoch, 1000); // explicit ts honoured
      expect(c.unreadFor('p1'), 1);
      expect(c.totalUnread, 1);
    });

    test('a duplicate message id is stored only once', () async {
      final c = await startController(pairedWith: ['p1']);
      final p1 = await peer('p1');

      await p1.send('127.0.0.1', c.tcpPort, FrameType.text,
          {'mid': 'dup', 'text': 'one'});
      await p1.send('127.0.0.1', c.tcpPort, FrameType.text,
          {'mid': 'dup', 'text': 'one-again'}); // same id → dropped
      await p1.send('127.0.0.1', c.tcpPort, FrameType.text,
          {'mid': 'm2', 'text': 'two'});

      await _waitFor(() => c.conversation('p1').any((m) => m.id == 'm2'));
      expect(c.conversation('p1').where((m) => m.id == 'dup'), hasLength(1));
      expect(c.conversation('p1'), hasLength(2));
    });

    test('a text frame with no text payload is ignored', () async {
      final c = await startController(pairedWith: ['p1']);
      final p1 = await peer('p1');

      await p1.send('127.0.0.1', c.tcpPort, FrameType.text, {'mid': 'empty'});
      await p1.send('127.0.0.1', c.tcpPort, FrameType.text,
          {'mid': 'm2', 'text': 'real'});

      await _waitFor(() => c.conversation('p1').any((m) => m.text == 'real'));
      expect(c.conversation('p1').where((m) => m.id == 'empty'), isEmpty);
    });

    test('a message without a timestamp is stamped at roughly now', () async {
      final before = DateTime.now().subtract(const Duration(seconds: 2));
      final c = await startController(pairedWith: ['p1']);
      final p1 = await peer('p1');

      await p1.send(
          '127.0.0.1', c.tcpPort, FrameType.text, {'mid': 'm1', 'text': 'hi'});

      await _waitFor(() => c.conversation('p1').isNotEmpty);
      final t = c.conversation('p1').single.sentAt;
      final after = DateTime.now().add(const Duration(seconds: 2));
      expect(t.isAfter(before) && t.isBefore(after), isTrue);
    });
  });

  group('photo frames', () {
    test('a photo from a paired peer is decoded, saved and recorded',
        () async {
      final c = await startController(pairedWith: ['p1']);
      final p1 = await peer('p1');

      await p1.send('127.0.0.1', c.tcpPort, FrameType.photo, {
        'mid': 'ph1',
        'name': 'cat.png',
        'mime': 'image/png',
        'data': base64Encode(_tinyPng),
      });

      await _waitFor(
          () => c.conversation('p1').any((m) => m.kind == MessageKind.photo));
      final msg =
          c.conversation('p1').firstWhere((m) => m.kind == MessageKind.photo);
      expect(msg.fileName, 'cat.png');
      expect(msg.mine, isFalse);
      expect(msg.filePath, isNotNull);
      expect(msg.filePath, startsWith(mediaDir.path)); // saved into our folder
      expect(File(msg.filePath!).readAsBytesSync(), _tinyPng);
      expect(c.unreadFor('p1'), 1);
    });

    test('a photo with undecodable data is dropped', () async {
      final c = await startController(pairedWith: ['p1']);
      final p1 = await peer('p1');

      await p1.send('127.0.0.1', c.tcpPort, FrameType.photo,
          {'mid': 'bad', 'name': 'x.png', 'data': '%%% not base64 %%%'});
      await p1.send('127.0.0.1', c.tcpPort, FrameType.text,
          {'mid': 'after', 'text': 'after'});

      await _waitFor(() => c.conversation('p1').any((m) => m.text == 'after'));
      expect(c.conversation('p1').where((m) => m.kind == MessageKind.photo),
          isEmpty);
    });

    test('a photo with no name is saved under a default name', () async {
      final c = await startController(pairedWith: ['p1']);
      final p1 = await peer('p1');

      await p1.send('127.0.0.1', c.tcpPort, FrameType.photo,
          {'mid': 'ph2', 'data': base64Encode(_tinyPng)}); // no name

      await _waitFor(
          () => c.conversation('p1').any((m) => m.kind == MessageKind.photo));
      final msg =
          c.conversation('p1').firstWhere((m) => m.kind == MessageKind.photo);
      expect(msg.fileName, 'photo');
    });
  });

  group('unpair frames', () {
    test('an unpair from a paired peer ends the agreement', () async {
      final c = await startController(pairedWith: ['p1']);
      expect(c.isPaired('p1'), isTrue);
      final p1 = await peer('p1');

      await p1.send('127.0.0.1', c.tcpPort, FrameType.unpair, const {});

      await _waitFor(() => !c.isPaired('p1'));
      expect(c.isPaired('p1'), isFalse);
    });

    test('an unpair from a stranger leaves existing peers untouched', () async {
      final c = await startController(pairedWith: ['p1']);
      final stranger = await peer('stranger', 'Nope');

      await stranger.send('127.0.0.1', c.tcpPort, FrameType.unpair, const {});

      await _waitFor(() => c.deviceFor('stranger') != null); // frame processed
      expect(c.isPaired('p1'), isTrue);
    });
  });

  group('device bookkeeping', () {
    test('any inbound frame learns where the peer can be reached', () async {
      final c = await startController(pairedWith: ['p1']);
      final p1 = await peer('p1');

      await p1.send(
          '127.0.0.1', c.tcpPort, FrameType.text, {'mid': 'm1', 'text': 'hi'});

      await _waitFor(() => c.deviceFor('p1') != null);
      final dev = c.deviceFor('p1')!;
      expect(dev.port, p1.port); // learned the sender's transport port
      expect(dev.host, anyOf('127.0.0.1', '::1'));
      expect(c.isOnline('p1'), isTrue);
    });

    test('markRead clears the unread counter for a peer', () async {
      final c = await startController(pairedWith: ['p1']);
      final p1 = await peer('p1');

      await p1.send(
          '127.0.0.1', c.tcpPort, FrameType.text, {'mid': 'm1', 'text': 'hi'});
      await _waitFor(() => c.unreadFor('p1') == 1);

      c.markRead('p1');
      expect(c.unreadFor('p1'), 0);
      expect(c.totalUnread, 0);
    });
  });
}

Future<void> _waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 8)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A minimal valid 1x1 PNG.
final List<int> _tinyPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
