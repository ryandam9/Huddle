// Tests for the resumable transfer queue: messages to an unreachable peer are
// persisted as `sending` and re-delivered automatically when the peer next
// appears — including a whole photo batch, and including across an app restart
// (a fresh controller over the same store). A `failed` message (peer reachable
// but unresponsive) is terminal and is not resurrected by later beacons.

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
    final d = Directory.systemTemp.createTempSync('huddle_resume_');
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
    SharedPreferences.setMockInitialValues(_seed(id, name, tempDir().path, pairedId));
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

  List<String> makePhotos(int n) {
    final dir = tempDir();
    return [
      for (var i = 0; i < n; i++)
        (File('${dir.path}/p$i.png')..writeAsBytesSync(_tinyPng)).path,
    ];
  }

  test('a queued photo batch resumes when the peer appears', () async {
    final a = await start('A', 'A', pairedId: 'B');
    final b = await start('B', 'B', pairedId: 'A');
    // Not wired yet → unreachable.

    await a.sendPhotos('B', makePhotos(3));
    final photos = a.conversation('B').where((m) => m.kind == MessageKind.photo);
    expect(photos, hasLength(3));
    expect(photos.every((m) => m.status == MessageStatus.sending), isTrue);

    wire(a, 'B', b); // peer appears → queue drains automatically
    await _waitFor(() =>
        b.conversation('A').where((m) => m.kind == MessageKind.photo).length ==
        3);
    await _waitFor(() => a
        .conversation('B')
        .where((m) => m.kind == MessageKind.photo)
        .every((m) => m.status == MessageStatus.delivered));
  });

  test('a queued message survives a restart and is resent when the peer appears',
      () async {
    final dir = tempDir().path;
    // First run: queue a message while the peer is absent, then "quit".
    SharedPreferences.setMockInitialValues(_seed('A', 'A', dir, 'B'));
    final a1 = HuddleController();
    await a1.init();
    await a1.sendText('B', 'survive the restart');
    expect(a1.conversation('B').single.status, MessageStatus.sending);
    a1.dispose(); // not tracked in `controllers`; disposed here

    // Second run: a fresh controller over the same store reloads the queue.
    final a2 = HuddleController();
    await a2.init();
    controllers.add(a2);
    expect(a2.conversation('B').single.text, 'survive the restart');
    expect(a2.conversation('B').single.status, MessageStatus.sending);

    // The peer comes online → the reloaded message is resent on its own.
    final b = await peer('B');
    final got = <String>[];
    b.onFrame = (f) {
      if (f.type == FrameType.text) got.add(f.data['text'] as String);
    };
    a2.ingestBeacon('127.0.0.1',
        Endpoint(id: 'B', name: 'B', platform: 'linux', port: b.port));

    await _waitFor(() => got.contains('survive the restart'));
  });

  test('a failed message is terminal and not resurrected by later beacons',
      () async {
    final a = await start('A', 'A', pairedId: 'p1');
    a.ackTimeout = const Duration(milliseconds: 120);
    a.maxSendAttempts = 1;

    final deaf = await peer('p1'); // reachable, but never acks
    var seen = 0;
    deaf.onFrame = (f) {
      if (f.type == FrameType.text) seen++;
    };
    a.ingestBeacon('127.0.0.1',
        Endpoint(id: 'p1', name: 'p1', platform: 'linux', port: deaf.port));

    await a.sendText('p1', 'no ack');
    await _waitFor(
        () => a.conversation('p1').single.status == MessageStatus.failed);
    final attemptsAtFailure = seen;

    // A later beacon must not resend a message we already gave up on.
    a.ingestBeacon('127.0.0.1',
        Endpoint(id: 'p1', name: 'p1', platform: 'linux', port: deaf.port));
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(a.conversation('p1').single.status, MessageStatus.failed);
    expect(seen, attemptsAtFailure);
  });
}

Map<String, Object> _seed(String id, String name, String media, String? pairedId) {
  final values = <String, Object>{
    'huddle.identity.id': id,
    'huddle.identity.name': name,
    'huddle.media.dir': media,
    // A unique discovery port per controller so neither sibling controllers nor
    // parallel test isolates cross-discover over the real UDP port; these tests
    // wire peers explicitly via ingestBeacon.
    'huddle.net.port': _isolatedPort(),
  };
  if (pairedId != null) {
    values['huddle.peers'] = jsonEncode([
      Peer(id: pairedId, name: pairedId, platform: 'linux', pairedAt: DateTime(2026))
          .toJson(),
    ]);
  }
  return values;
}

// A unique, valid discovery port per controller (random base per isolate +
// counter) so no two controllers ever share a port and auto-discover.
int _portSeq = 30000 + Random().nextInt(20000);
int _isolatedPort() => _portSeq++;

Future<void> _waitFor(bool Function() cond,
    {Duration timeout = const Duration(seconds: 10)}) async {
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
