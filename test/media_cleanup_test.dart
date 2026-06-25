// Tests for the media-file deletion policy: a photo's stored file is removed
// from Huddle's own media folder when its message is deleted, its conversation
// is cleared, or the peer is unpaired — while a file the user redirected to a
// custom download folder of their own is left untouched.
//
// path_provider is mocked to a temp directory so the default media folder is a
// real, writable location; a raw TransportService stands in for the peer.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart' as sembast;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/models/peer.dart';
import 'package:huddle/services/protocol.dart';
import 'package:huddle/services/transport_service.dart';
import 'package:huddle/state/huddle_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  final controllers = <HuddleController>[];
  final transports = <TransportService>[];

  setUp(() {
    docs = Directory.systemTemp.createTempSync('huddle_docs_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => docs.path,
    );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    for (final c in controllers) {
      c.dispose();
    }
    for (final t in transports) {
      await t.dispose();
    }
    controllers.clear();
    transports.clear();
    if (docs.existsSync()) docs.deleteSync(recursive: true);
  });

  Future<HuddleController> start({String? downloadDir}) async {
    SharedPreferences.setMockInitialValues({
      'huddle.peers': jsonEncode([
        Peer(id: 'p1', name: 'p1', platform: 'linux', pairedAt: DateTime(2026))
            .toJson(),
      ]),
      'huddle.media.dir': ?downloadDir,
    });
    final c =
        HuddleController(databaseFactory: sembast.newDatabaseFactoryMemory());
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

  /// Sends a photo from [from] to [c], waits for it to land, and returns the
  /// absolute path of the file Huddle stored for it.
  Future<String> receivePhoto(
      HuddleController c, TransportService from, String mid) async {
    await from.send('127.0.0.1', c.tcpPort, FrameType.photo, {
      'mid': mid,
      'name': '$mid.png',
      'data': base64Encode(_tinyPng),
    });
    await _waitFor(() => c.conversation('p1').any((m) => m.id == mid));
    return c.conversation('p1').firstWhere((m) => m.id == mid).filePath!;
  }

  test('deleting a photo message removes its file from the managed folder',
      () async {
    final c = await start();
    final s = await peer('p1');
    final path = await receivePhoto(c, s, 'PH1');
    expect(File(path).existsSync(), isTrue);
    expect(path, startsWith(docs.path)); // Huddle's own folder

    expect(await c.deleteMessage('p1', 'PH1'), isTrue);
    expect(File(path).existsSync(), isFalse); // cleaned up
  });

  test('clearing a conversation removes all its photo files', () async {
    final c = await start();
    final s = await peer('p1');
    final a = await receivePhoto(c, s, 'PH1');
    final b = await receivePhoto(c, s, 'PH2');

    await c.clearConversation('p1');
    expect(File(a).existsSync(), isFalse);
    expect(File(b).existsSync(), isFalse);
  });

  test('unpairing removes the conversation photo files', () async {
    final c = await start();
    final s = await peer('p1');
    final path = await receivePhoto(c, s, 'PH1');

    await c.unpair('p1');
    expect(File(path).existsSync(), isFalse);
  });

  test('a file in a user-chosen download folder is left in place', () async {
    final custom = Directory('${docs.path}/my_downloads')..createSync();
    final c = await start(downloadDir: custom.path);
    final s = await peer('p1');
    final path = await receivePhoto(c, s, 'PH1');
    expect(path, startsWith(custom.path)); // saved into the user's folder

    expect(await c.deleteMessage('p1', 'PH1'), isTrue);
    expect(File(path).existsSync(), isTrue); // the user's folder is untouched
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
