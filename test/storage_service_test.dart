// Tests for the persistence layer that is backed purely by SharedPreferences
// (peers and conversation history). The photo-on-disk path uses path_provider
// and is exercised by integration testing rather than here.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/models/chat_message.dart';
import 'package:huddle/models/peer.dart';
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

  group('conversations', () {
    test('start empty', () {
      expect(storage.loadMessages('p1'), isEmpty);
    });

    test('persist, reload and delete', () async {
      final messages = [
        ChatMessage(
          id: 'm1',
          peerId: 'p1',
          mine: true,
          kind: MessageKind.text,
          sentAt: DateTime.fromMillisecondsSinceEpoch(10),
          text: 'hi',
        ),
        ChatMessage(
          id: 'm2',
          peerId: 'p1',
          mine: false,
          kind: MessageKind.text,
          sentAt: DateTime.fromMillisecondsSinceEpoch(20),
          text: 'hello',
        ),
      ];
      await storage.saveMessages('p1', messages);

      final loaded = storage.loadMessages('p1');
      expect(loaded.length, 2);
      expect(loaded.first.text, 'hi');
      expect(loaded.last.mine, isFalse);

      await storage.deleteConversation('p1');
      expect(storage.loadMessages('p1'), isEmpty);
    });

    test('conversations are isolated per peer', () async {
      await storage.saveMessages('p1', [
        ChatMessage(
          id: 'm1',
          peerId: 'p1',
          mine: true,
          kind: MessageKind.text,
          sentAt: DateTime.fromMillisecondsSinceEpoch(1),
          text: 'for p1',
        ),
      ]);
      expect(storage.loadMessages('p1'), hasLength(1));
      expect(storage.loadMessages('p2'), isEmpty);
    });
  });
}
