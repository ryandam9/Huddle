// Tests for delivery acknowledgement and bounded retry (protocol v3). The
// receiver returns an `ack` frame for every stored photo — and for duplicates,
// so a retry whose earlier ack was lost still clears — while a reliable batch
// send retries until acknowledged and only then counts a file as delivered.
//
// A raw TransportService stands in for the remote peer so we can both observe
// the acks it receives and simulate one that never acknowledges.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' as sembast;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/models/chat_message.dart';
import 'package:huddle/models/peer.dart';
import 'package:huddle/services/protocol.dart';
import 'package:huddle/services/transport_service.dart';
import 'package:huddle/state/huddle_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory mediaDir;
  final controllers = <HuddleController>[];
  final transports = <TransportService>[];

  setUp(() => mediaDir = Directory.systemTemp.createTempSync('huddle_ack_'));

  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    for (final t in transports) {
      await t.dispose();
    }
    controllers.clear();
    transports.clear();
    if (mediaDir.existsSync()) mediaDir.deleteSync(recursive: true);
  });

  Future<HuddleController> startController(
      {List<String> pairedWith = const []}) async {
    final values = <String, Object>{'huddle.media.dir': mediaDir.path};
    if (pairedWith.isNotEmpty) {
      values['huddle.peers'] = jsonEncode([
        for (final id in pairedWith)
          Peer(id: id, name: id, platform: 'linux', pairedAt: DateTime(2026))
              .toJson(),
      ]);
    }
    SharedPreferences.setMockInitialValues(values);
    final c = HuddleController(databaseFactory: sembast.newDatabaseFactoryMemory());
    await c.init();
    controllers.add(c);
    expect(c.tcpPort, greaterThan(0));
    return c;
  }

  Future<TransportService> peer(String id) async {
    final t = TransportService(id: id, name: id, platform: 'android');
    await t.start();
    transports.add(t);
    return t;
  }

  String photoData(String mid) =>
      jsonEncode({'mid': mid, 'name': '$mid.png', 'data': base64Encode(_tinyPng)});

  test('the protocol version is bumped and the ack frame is defined', () {
    expect(kProtocolVersion, greaterThanOrEqualTo(3)); // ack landed in v3
    expect(FrameType.ack, 'ack');
  });

  test('the receiver acknowledges a stored photo', () async {
    final c = await startController(pairedWith: ['p1']);
    final s = await peer('p1');
    final acks = <String>[];
    s.onFrame = (f) {
      if (f.type == FrameType.ack) acks.add(f.data['mid'] as String);
    };

    await s.send('127.0.0.1', c.tcpPort, FrameType.photo,
        jsonDecode(photoData('PH1')) as Map<String, dynamic>);

    await _waitFor(() => acks.contains('PH1'));
    expect(c.conversation('p1').where((m) => m.kind == MessageKind.photo),
        hasLength(1));
  });

  test('a duplicate photo is acknowledged again but stored only once',
      () async {
    final c = await startController(pairedWith: ['p1']);
    final s = await peer('p1');
    final acks = <String>[];
    s.onFrame = (f) {
      if (f.type == FrameType.ack) acks.add(f.data['mid'] as String);
    };

    final frame = jsonDecode(photoData('PH1')) as Map<String, dynamic>;
    await s.send('127.0.0.1', c.tcpPort, FrameType.photo, frame);
    await _waitFor(() => acks.isNotEmpty);
    await s.send('127.0.0.1', c.tcpPort, FrameType.photo, frame); // retry
    await _waitFor(() => acks.length >= 2);

    expect(acks.every((m) => m == 'PH1'), isTrue);
    expect(c.conversation('p1').where((m) => m.kind == MessageKind.photo),
        hasLength(1)); // de-duplicated despite two deliveries
  });

  test('a reliable batch retries and finally fails when no ack arrives',
      () async {
    final a = await startController(pairedWith: ['p1']);
    a.ackTimeout = const Duration(milliseconds: 150);
    a.maxSendAttempts = 2;

    // A peer that receives photo frames but never acknowledges them (an old
    // v2 peer, or a dropped ack).
    final deaf = await peer('p1');
    var photosSeen = 0;
    deaf.onFrame = (f) {
      if (f.type == FrameType.photo) photosSeen++;
    };
    a.ingestBeacon('127.0.0.1',
        Endpoint(id: 'p1', name: 'p1', platform: 'linux', port: deaf.port));

    final src = File('${mediaDir.path}/x.png')..writeAsBytesSync(_tinyPng);
    await a.sendPhotos('p1', [src.path]);

    expect(a.transfer!.total, 1);
    expect(a.transfer!.sent, 0);
    expect(a.transfer!.failed, 1);
    // The frame really went out, once per attempt — it just wasn't acked.
    await _waitFor(() => photosSeen >= 2);
    expect(photosSeen, 2);
  });
}

Future<void> _waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 5)}) async {
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
