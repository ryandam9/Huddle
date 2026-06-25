// Regression tests for the hardening pass: a forged ack from the wrong peer
// can't mark a message delivered, a remote unpair clears history (not just the
// peer), and a batch that throws doesn't poison future batch sends.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' as sembast;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/models/chat_message.dart';
import 'package:huddle/models/peer.dart';
import 'package:huddle/services/foreground_service.dart';
import 'package:huddle/services/protocol.dart';
import 'package:huddle/services/transport_service.dart';
import 'package:huddle/state/huddle_controller.dart';

class _ThrowingForeground implements ForegroundService {
  @override
  Future<void> start(String message) async => throw StateError('boom');
  @override
  Future<void> stop() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final controllers = <HuddleController>[];
  final transports = <TransportService>[];
  final tempDirs = <Directory>[];

  Directory tempDir() {
    final d = Directory.systemTemp.createTempSync('huddle_hard_');
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
      {String? pairedId, ForegroundService? foreground}) async {
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
    final c = HuddleController(
        foreground: foreground,
        databaseFactory: sembast.newDatabaseFactoryMemory());
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

  List<String> makePhotos(int n) {
    final dir = tempDir();
    return [
      for (var i = 0; i < n; i++)
        (File('${dir.path}/p$i.png')..writeAsBytesSync(_tinyPng)).path,
    ];
  }

  test('an ack from the wrong peer does not mark a message delivered',
      () async {
    final a = await start('A', 'A', pairedId: 'p1');
    a.ackTimeout = const Duration(milliseconds: 400);
    a.maxSendAttempts = 1;
    final deaf = await peer('p1'); // the real recipient, which never acks
    wire(a, 'p1', deaf.port);

    await a.sendText('p1', 'secret');
    final mid = a.conversation('p1').single.id;

    // An unrelated device forges an ack for that message id.
    final evil = await peer('evil');
    await evil.send('127.0.0.1', a.tcpPort, FrameType.ack, {'mid': mid});

    // The forged ack is rejected (wrong sender); with no genuine ack the
    // message ends up failed rather than falsely delivered.
    await _waitFor(
        () => a.conversation('p1').single.status == MessageStatus.failed);
    expect(a.conversation('p1').single.status, isNot(MessageStatus.delivered));
  });

  test('a remote unpair clears the conversation and unread, not just the peer',
      () async {
    final a = await start('A', 'A', pairedId: 'p1');
    final p1 = await peer('p1');
    await p1.send('127.0.0.1', a.tcpPort, FrameType.text, {'mid': 'm1', 'text': 'hi'});
    await _waitFor(() => a.conversation('p1').isNotEmpty);
    expect(a.unreadFor('p1'), 1);

    await p1.send('127.0.0.1', a.tcpPort, FrameType.unpair, const {});

    await _waitFor(() => !a.isPaired('p1'));
    expect(a.conversation('p1'), isEmpty);
    expect(a.unreadFor('p1'), 0);
  });

  test('a batch that throws does not poison future batch sends', () async {
    final a =
        await start('A', 'A', pairedId: 'B', foreground: _ThrowingForeground());
    final b = await start('B', 'B', pairedId: 'A');
    wire(a, 'B', b.tcpPort);

    // _runBatch throws (the fake foreground throws on start); the chain must
    // recover so this await completes instead of hanging…
    await a
        .sendPhotos('B', makePhotos(1))
        .timeout(const Duration(seconds: 5));
    // …and a subsequent batch still runs (the chain isn't stuck on a failure).
    await a
        .sendPhotos('B', makePhotos(1))
        .timeout(const Duration(seconds: 5));
  });
}

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

final List<int> _tinyPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
