// Tests for retrying a failed send. A message that failed (the peer was
// reachable but never acknowledged it) is terminal until the user retries it:
// retryMessage resets it to `sending` and re-runs the queue, so it goes out
// again and is delivered once a peer that actually acks is reachable. Only a
// failed outgoing message can be retried.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

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
    final d = Directory.systemTemp.createTempSync('huddle_retry_');
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
      'huddle.net.port': _isolatedPort(),
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

  void wire(HuddleController from, String toId, int port) {
    from.ingestBeacon('127.0.0.1',
        Endpoint(id: toId, name: toId, platform: 'linux', port: port));
  }

  test('only a failed outgoing message can be retried', () async {
    final c = await start('C', 'C', pairedId: 'p1');
    final s = await peer('p1');
    await s.send('127.0.0.1', c.tcpPort, FrameType.text, {'mid': 'RX1', 'text': 'hi'});
    await _waitFor(() => c.conversation('p1').any((m) => m.id == 'RX1'));

    expect(c.retryMessage('p1', 'RX1'), isFalse); // received (not ours)
    expect(c.retryMessage('p1', 'no-such-mid'), isFalse); // unknown message
    expect(c.retryMessage('absent', 'RX1'), isFalse); // unknown peer
  });

  test('retrying a failed message sends it again', () async {
    final a = await start('A', 'A', pairedId: 'p1');
    a.ackTimeout = const Duration(milliseconds: 120);
    a.maxSendAttempts = 1;
    final deaf = await peer('p1'); // reachable, never acks
    var seen = 0;
    deaf.onFrame = (f) {
      if (f.type == FrameType.text) seen++;
    };
    wire(a, 'p1', deaf.port);

    await a.sendText('p1', 'no ack');
    await _waitFor(
        () => a.conversation('p1').single.status == MessageStatus.failed);
    expect(seen, 1);

    expect(a.retryMessage('p1', a.conversation('p1').single.id), isTrue);
    await _waitFor(() => seen == 2); // the frame went out a second time
    // Let the retry settle (back to failed against the deaf peer) so no
    // background delivery outlives the test and touches a disposed controller.
    await _waitFor(
        () => a.conversation('p1').single.status == MessageStatus.failed);
  });

  test('a failed message delivers after retry once a real peer is reachable',
      () async {
    final a = await start('A', 'A', pairedId: 'p1');
    a.ackTimeout = const Duration(milliseconds: 120);
    a.maxSendAttempts = 1;
    final deaf = await peer('p1');
    wire(a, 'p1', deaf.port);

    await a.sendText('p1', 'later');
    await _waitFor(
        () => a.conversation('p1').single.status == MessageStatus.failed);
    final mid = a.conversation('p1').single.id;

    // A real, acking peer 'p1' comes online; point delivery at it and retry.
    final b = await start('p1', 'Peer', pairedId: 'A');
    wire(a, 'p1', b.tcpPort);

    expect(a.retryMessage('p1', mid), isTrue);
    await _waitFor(
        () => a.conversation('p1').single.status == MessageStatus.delivered);
    await _waitFor(
        () => b.conversation('A').any((m) => m.text == 'later' && !m.mine));

    // Retrying a delivered message is a no-op.
    expect(a.retryMessage('p1', mid), isFalse);
  });
}

// A unique, valid discovery port per controller (random base per isolate +
// counter) so no two controllers ever share a port and auto-discover.
int _portSeq = 30000 + Random().nextInt(20000);
int _isolatedPort() => _portSeq++;

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
