// Tests for reliable text delivery: an outgoing message is shown immediately
// as `sending`, advances to `delivered` once the peer acknowledges it, or
// `failed` if it can't be delivered. The receiver acks every text frame (and
// duplicates), and received/historical messages are always `delivered`.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/models/chat_message.dart';
import 'package:huddle/models/peer.dart';
import 'package:huddle/services/protocol.dart';
import 'package:huddle/services/transport_service.dart';
import 'package:huddle/state/huddle_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final controllers = <HuddleController>[];
  final transports = <TransportService>[];
  final tempDirs = <Directory>[];

  Directory tempDir() {
    final d = Directory.systemTemp.createTempSync('huddle_text_');
    tempDirs.add(d);
    return d;
  }

  tearDown(() async {
    for (final c in controllers) {
      c.dispose();
    }
    for (final t in transports) {
      await t.dispose();
    }
    controllers.clear();
    transports.clear();
    for (final d in tempDirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    tempDirs.clear();
  });

  Future<HuddleController> start(String id, String name,
      {String? pairedId}) async {
    final values = <String, Object>{
      'huddle.identity.id': id,
      'huddle.identity.name': name,
      'huddle.media.dir': tempDir().path,
    };
    if (pairedId != null) {
      values['huddle.peers'] = jsonEncode([
        Peer(id: pairedId, name: pairedId, platform: 'linux', pairedAt: DateTime(2026))
            .toJson(),
      ]);
    }
    SharedPreferences.setMockInitialValues(values);
    final c = HuddleController();
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

  void wire(HuddleController from, String toId, HuddleController to) {
    from.ingestBeacon('127.0.0.1',
        Endpoint(id: toId, name: toId, platform: 'linux', port: to.tcpPort));
  }

  test('the receiver acknowledges a stored text message', () async {
    final c = await start('C', 'C', pairedId: 'p1');
    final s = await peer('p1');
    final acks = <String>[];
    s.onFrame = (f) {
      if (f.type == FrameType.ack) acks.add(f.data['mid'] as String);
    };

    await s.send('127.0.0.1', c.tcpPort, FrameType.text, {'mid': 'T1', 'text': 'hi'});

    await _waitFor(() => acks.contains('T1'));
    expect(c.conversation('p1').single.text, 'hi');
  });

  test('an outgoing text becomes delivered once acknowledged', () async {
    final a = await start('A', 'A', pairedId: 'B');
    final b = await start('B', 'B', pairedId: 'A');
    wire(a, 'B', b);

    await a.sendText('B', 'hello there');
    // Stored optimistically right away.
    expect(a.conversation('B').single.text, 'hello there');

    await _waitFor(
        () => a.conversation('B').single.status == MessageStatus.delivered);
    await _waitFor(() =>
        b.conversation('A').any((m) => m.text == 'hello there' && !m.mine));
  });

  test('an outgoing text shows as sending, then failed when never acked',
      () async {
    final a = await start('A', 'A', pairedId: 'p1');
    a.ackTimeout = const Duration(milliseconds: 150);
    a.maxSendAttempts = 1;
    final deaf = await peer('p1'); // receives the frame but never acks
    a.ingestBeacon('127.0.0.1',
        Endpoint(id: 'p1', name: 'p1', platform: 'linux', port: deaf.port));

    await a.sendText('p1', 'hi');
    // The ack round-trip is still outstanding at this point.
    expect(a.conversation('p1').single.status, MessageStatus.sending);

    await _waitFor(
        () => a.conversation('p1').single.status == MessageStatus.failed);
  });

  test('a text to a peer with no known endpoint fails', () async {
    final a = await start('A', 'A', pairedId: 'GHOST');

    final ok = await a.sendText('GHOST', 'anyone home?');
    expect(ok, isTrue); // accepted and stored

    await _waitFor(
        () => a.conversation('GHOST').single.status == MessageStatus.failed);
  });

  test('received and legacy messages count as delivered', () async {
    final c = await start('C', 'C', pairedId: 'p1');
    final s = await peer('p1');
    await s.send('127.0.0.1', c.tcpPort, FrameType.text, {'mid': 'R1', 'text': 'yo'});

    await _waitFor(() => c.conversation('p1').isNotEmpty);
    expect(c.conversation('p1').single.mine, isFalse);
    expect(c.conversation('p1').single.status, MessageStatus.delivered);

    // A record persisted before this feature (no `status`) decodes as delivered.
    final legacy = ChatMessage.fromJson(
        {'id': 'x', 'peerId': 'p1', 'kind': 'text', 'sentAt': 0, 'text': 'old'});
    expect(legacy.status, MessageStatus.delivered);
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
