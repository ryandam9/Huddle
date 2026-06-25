// Tests for the persistence layer that is backed purely by SharedPreferences
// (peers and network/download settings). Conversation history now lives in the
// database and is covered by message_store_test. The photo-on-disk path uses
// path_provider and is exercised by integration testing rather than here.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/models/peer.dart';
import 'package:huddle/services/protocol.dart';
import 'package:huddle/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService(await SharedPreferences.getInstance());
  });

  group('peers', () {
    test('start empty', () {
      expect(storage.loadPeers(), isEmpty);
    });

    test('persist and reload', () async {
      final peers = [
        Peer(
            id: 'p1',
            name: 'Laptop',
            platform: 'macos',
            pairedAt: DateTime.fromMillisecondsSinceEpoch(1)),
        Peer(
            id: 'p2',
            name: 'Phone',
            platform: 'android',
            pairedAt: DateTime.fromMillisecondsSinceEpoch(2)),
      ];
      await storage.savePeers(peers);

      final loaded = storage.loadPeers();
      expect(loaded.map((p) => p.id), ['p1', 'p2']);
      expect(loaded.map((p) => p.name), ['Laptop', 'Phone']);
    });
  });

  group('network settings', () {
    test('sensible defaults', () {
      expect(storage.loadDiscoveryPort(), kDiscoveryPort);
      expect(storage.loadCustomBroadcast(), isNull);
    });

    test('discovery port persists', () async {
      await storage.saveDiscoveryPort(50321);
      expect(storage.loadDiscoveryPort(), 50321);
    });

    test('custom broadcast persists, and blank/null clears it', () async {
      await storage.saveCustomBroadcast('192.168.0.255');
      expect(storage.loadCustomBroadcast(), '192.168.0.255');

      await storage.saveCustomBroadcast('   ');
      expect(storage.loadCustomBroadcast(), isNull);

      await storage.saveCustomBroadcast('10.0.0.255');
      await storage.saveCustomBroadcast(null);
      expect(storage.loadCustomBroadcast(), isNull);
    });
  });

  group('media', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('huddle_media_test'));
    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      PathProviderPlatform.instance = _UnsetPathProvider();
    });

    test('saves an incoming file into the chosen custom folder', () async {
      final dest = Directory('${tmp.path}/downloads');
      SharedPreferences.setMockInitialValues({'huddle.media.dir': dest.path});
      final store = StorageService(await SharedPreferences.getInstance());

      final path = await store.saveIncomingPhoto('pic.jpg', [1, 2, 3]);

      expect(path, startsWith(dest.path));
      expect(File(path).readAsBytesSync(), [1, 2, 3]);
    });

    test('two files with the same name get distinct paths', () async {
      final dest = Directory('${tmp.path}/downloads');
      SharedPreferences.setMockInitialValues({'huddle.media.dir': dest.path});
      final store = StorageService(await SharedPreferences.getInstance());

      final a = await store.saveIncomingPhoto('pic.jpg', [1]);
      final b = await store.saveIncomingPhoto('pic.jpg', [2]);

      expect(a, isNot(b)); // no collision/overwrite
      expect(File(a).readAsBytesSync(), [1]);
      expect(File(b).readAsBytesSync(), [2]);
    });

    test('falls back to the default folder when the custom one is unwritable',
        () async {
      // A file where a directory is expected makes the custom folder impossible
      // to create — standing in for a moved folder or an expired sandbox grant.
      final blocker = File('${tmp.path}/blocker')..writeAsStringSync('x');
      final fallback = Directory('${tmp.path}/container');
      PathProviderPlatform.instance = _FakePathProvider(fallback.path);

      SharedPreferences.setMockInitialValues(
          {'huddle.media.dir': '${blocker.path}/nope'});
      final store = StorageService(await SharedPreferences.getInstance());

      final path = await store.saveIncomingPhoto('pic.jpg', [4, 5, 6]);

      expect(path, startsWith('${fallback.path}/huddle_media'));
      expect(File(path).readAsBytesSync(), [4, 5, 6]);
    });
  });
}

/// Returns a fixed documents path so the default download folder is
/// deterministic in tests (path_provider has no real platform here).
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.documentsPath);
  final String documentsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => documentsPath;
}

/// Restores a no-op provider between tests so a stale fake can't leak.
class _UnsetPathProvider extends PathProviderPlatform {
  @override
  Future<String?> getApplicationDocumentsPath() async => null;
}
