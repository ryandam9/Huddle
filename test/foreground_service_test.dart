// Tests for the foreground-service orchestration: a background batch brackets
// its delivery with foreground-service start/stop (so Android can keep the
// process alive), while quick single sends don't. The native service itself is
// Android-only and validated on a device; here we inject a fake and assert the
// controller drives it at the right times.

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
import 'package:huddle/state/huddle_controller.dart';

class _FakeForeground implements ForegroundService {
  int starts = 0;
  int stops = 0;
  String? lastMessage;

  @override
  Future<void> start(String message) async {
    starts++;
    lastMessage = message;
  }

  @override
  Future<void> stop() async => stops++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final controllers = <HuddleController>[];
  final tempDirs = <Directory>[];

  Directory tempDir() {
    final d = Directory.systemTemp.createTempSync('huddle_fg_');
    tempDirs.add(d);
    return d;
  }

  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
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

  test('a batch brackets delivery with foreground start/stop', () async {
    final fg = _FakeForeground();
    final a = await start('A', 'A', pairedId: 'B', foreground: fg);
    final b = await start('B', 'B', pairedId: 'A');
    wire(a, 'B', b.tcpPort);

    await a.sendPhotos('B', makePhotos(3));

    expect(fg.starts, 1);
    expect(fg.stops, 1);
    expect(fg.lastMessage, contains('photos'));
    await _waitFor(() => b
        .conversation('A')
        .where((m) => m.kind == MessageKind.photo)
        .length ==
        3);
  });

  test('a single text send does not start the foreground service', () async {
    final fg = _FakeForeground();
    final a = await start('A', 'A', pairedId: 'p1', foreground: fg);

    await a.sendText('p1', 'hi'); // no batch → no foreground service

    expect(fg.starts, 0);
    expect(fg.stops, 0);
  });

  test('an unreachable batch still stops the service it started', () async {
    final fg = _FakeForeground();
    final a = await start('A', 'A', pairedId: 'GHOST', foreground: fg);

    await a.sendPhotos('GHOST', makePhotos(2)); // queued; nothing delivered

    expect(fg.starts, 1);
    expect(fg.stops, 1); // bracketed cleanly via the finally
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
