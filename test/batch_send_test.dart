// End-to-end tests for background batch photo sending: a paired sender pushes
// several photos to a paired receiver one after another, the receiver ends up
// with every file on disk, and the sender's TransferProgress tracks the counts.
// Devices are wired with ingestBeacon and pairing is seeded into storage so the
// tests don't depend on UDP discovery or the interactive handshake.

import 'dart:convert';
import 'dart:io';

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
    final d = Directory.systemTemp.createTempSync('huddle_batch_');
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

  /// Starts a controller with its own identity and received-file folder,
  /// optionally already paired with [pairedId].
  Future<HuddleController> start(
    String id,
    String name, {
    String? pairedId,
    String? pairedName,
  }) async {
    final values = <String, Object>{
      'huddle.identity.id': id,
      'huddle.identity.name': name,
      'huddle.media.dir': tempDir().path,
    };
    if (pairedId != null) {
      values['huddle.peers'] = jsonEncode([
        Peer(
          id: pairedId,
          name: pairedName ?? pairedId,
          platform: 'linux',
          pairedAt: DateTime(2026),
        ).toJson(),
      ]);
    }
    SharedPreferences.setMockInitialValues(values);
    final c = HuddleController(databaseFactory: sembast.newDatabaseFactoryMemory());
    await c.init();
    controllers.add(c);
    expect(c.tcpPort, greaterThan(0),
        reason: 'transport must be listening for the batch tests to run');
    return c;
  }

  /// Writes [n] tiny PNG files and returns their paths.
  List<String> makePhotos(int n) {
    final dir = tempDir();
    return [
      for (var i = 0; i < n; i++)
        (File('${dir.path}/photo_$i.png')..writeAsBytesSync(_tinyPng)).path,
    ];
  }

  void wire(HuddleController from, String toId, HuddleController to) {
    from.ingestBeacon(
      '127.0.0.1',
      Endpoint(id: toId, name: toId, platform: 'linux', port: to.tcpPort),
    );
  }

  test('sends every photo in a batch to a paired peer', () async {
    final a =
        await start('AAAA', 'Device A', pairedId: 'BBBB', pairedName: 'Device B');
    final b =
        await start('BBBB', 'Device B', pairedId: 'AAAA', pairedName: 'Device A');
    wire(a, 'BBBB', b);

    await a.sendPhotos('BBBB', makePhotos(3));

    // The sender's progress reflects a fully delivered batch.
    expect(a.transfer, isNotNull);
    expect(a.transfer!.total, 3);
    expect(a.transfer!.sent, 3);
    expect(a.transfer!.failed, 0);
    expect(a.transfer!.isComplete, isTrue);

    // The sender keeps a local copy of each (one bubble per photo).
    expect(a.conversation('BBBB').where((m) => m.kind == MessageKind.photo),
        hasLength(3));

    // The receiver ends up with all three, saved to disk.
    await _waitFor(() =>
        b.conversation('AAAA').where((m) => m.kind == MessageKind.photo).length ==
        3);
    for (final m
        in b.conversation('AAAA').where((m) => m.kind == MessageKind.photo)) {
      expect(m.mine, isFalse);
      expect(File(m.filePath!).existsSync(), isTrue);
    }
  });

  test('queues a batch when the peer is unreachable', () async {
    // Paired, but with no device endpoint → the batch is stored and queued.
    final a = await start('AAAA', 'Device A', pairedId: 'GHOST');

    await a.sendPhotos('GHOST', makePhotos(2));

    // Nothing could be sent yet, so there's no active progress…
    expect(a.transfer, isNull);
    // …but both files are persisted as queued, ready to resume on reconnect.
    final photos =
        a.conversation('GHOST').where((m) => m.kind == MessageKind.photo);
    expect(photos, hasLength(2));
    expect(photos.every((m) => m.status == MessageStatus.sending), isTrue);
  });

  test('an empty selection starts no transfer', () async {
    final a = await start('AAAA', 'Device A', pairedId: 'BBBB');
    await a.sendPhotos('BBBB', const []);
    expect(a.transfer, isNull);
  });

  test('a batch to an unpaired peer is ignored', () async {
    final a = await start('AAAA', 'Device A'); // no peers
    await a.sendPhotos('stranger', makePhotos(2));
    expect(a.transfer, isNull);
    expect(a.conversation('stranger'), isEmpty);
  });

  test('sendPhoto to an offline paired peer queues it and returns true',
      () async {
    // Paired, but never wired → unreachable. A queued send is a success, not a
    // failure: it returns true and the message simply waits as `sending`.
    final a = await start('AAAA', 'Device A', pairedId: 'GHOST');

    final ok = await a.sendPhoto('GHOST', makePhotos(1).single);

    expect(ok, isTrue);
    final photo = a.conversation('GHOST').single;
    expect(photo.kind, MessageKind.photo);
    expect(photo.status, MessageStatus.sending); // queued for later delivery
  });

  test('sendPhoto to an unpaired id is rejected and stores nothing', () async {
    final a = await start('AAAA', 'Device A'); // no peers
    expect(await a.sendPhoto('nobody', makePhotos(1).single), isFalse);
    expect(a.conversation('nobody'), isEmpty);
  });

  test('successive batches are serialised and all files arrive', () async {
    final a =
        await start('AAAA', 'Device A', pairedId: 'BBBB', pairedName: 'Device B');
    final b =
        await start('BBBB', 'Device B', pairedId: 'AAAA', pairedName: 'Device A');
    wire(a, 'BBBB', b);

    final first = a.sendPhotos('BBBB', makePhotos(2));
    final second = a.sendPhotos('BBBB', makePhotos(3));
    await Future.wait([first, second]);

    // The chain runs them back to back; the final snapshot is the last batch.
    expect(a.transfer!.total, 3);
    expect(a.transfer!.sent, 3);

    await _waitFor(() =>
        b.conversation('AAAA').where((m) => m.kind == MessageKind.photo).length ==
        5);
  });
}

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

/// A minimal valid 1x1 PNG.
final List<int> _tinyPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];
