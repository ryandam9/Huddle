// Tests for read receipts. When a peer opens a conversation (markRead) it sends
// a `read` frame naming the messages it just read; the original sender upgrades
// those messages from `delivered` to `read`. Receipts are incremental (only
// newly-read ids) and best-effort.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' as sembast;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/models/chat_message.dart';
import 'package:huddle/models/peer.dart';
import 'package:huddle/services/protocol.dart';
import 'package:huddle/state/huddle_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final controllers = <HuddleController>[];
  final tempDirs = <Directory>[];

  Directory tempDir() {
    final d = Directory.systemTemp.createTempSync('huddle_read_');
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
    final c = HuddleController(databaseFactory: sembast.newDatabaseFactoryMemory());
    await c.init();
    controllers.add(c);
    expect(c.tcpPort, greaterThan(0));
    return c;
  }

  void wire(HuddleController from, String toId, int port) {
    from.ingestBeacon('127.0.0.1',
        Endpoint(id: toId, name: toId, platform: 'linux', port: port));
  }

  test('the read frame is defined at protocol v4', () {
    expect(kProtocolVersion, 4);
    expect(FrameType.read, 'read');
  });

  test('a read receipt upgrades a delivered message to read', () async {
    final a = await start('A', 'A', pairedId: 'B');
    final b = await start('B', 'B', pairedId: 'A');
    wire(a, 'B', b.tcpPort); // a knows where b is; b learns a from the frame

    await a.sendText('B', 'seen me?');
    await _waitFor(
        () => a.conversation('B').single.status == MessageStatus.delivered);
    await _waitFor(() => b.conversation('A').any((m) => m.text == 'seen me?'));

    b.markRead('A'); // b opens the conversation
    await _waitFor(
        () => a.conversation('B').single.status == MessageStatus.read);
  });

  test('read receipts are incremental across messages', () async {
    final a = await start('A', 'A', pairedId: 'B');
    final b = await start('B', 'B', pairedId: 'A');
    wire(a, 'B', b.tcpPort);

    await a.sendText('B', 'one');
    await _waitFor(() => b.conversation('A').any((m) => m.text == 'one'));
    b.markRead('A');
    await _waitFor(() =>
        a.conversation('B').firstWhere((m) => m.text == 'one').status ==
        MessageStatus.read);

    await a.sendText('B', 'two');
    await _waitFor(() => b.conversation('A').any((m) => m.text == 'two'));
    b.markRead('A');
    await _waitFor(() =>
        a.conversation('B').firstWhere((m) => m.text == 'two').status ==
        MessageStatus.read);

    // Both ended up read.
    expect(
        a.conversation('B').where((m) => m.status == MessageStatus.read).length,
        2);
  });

  test('markRead with nothing newly received does not disturb prior state',
      () async {
    final a = await start('A', 'A', pairedId: 'B');
    final b = await start('B', 'B', pairedId: 'A');
    wire(a, 'B', b.tcpPort);

    await a.sendText('B', 'hi');
    await _waitFor(() => b.conversation('A').any((m) => m.text == 'hi'));
    b.markRead('A');
    await _waitFor(
        () => a.conversation('B').single.status == MessageStatus.read);

    // A second open with nothing new to read is a harmless no-op.
    b.markRead('A');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(a.conversation('B').single.status, MessageStatus.read);
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
