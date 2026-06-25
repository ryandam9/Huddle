// Tests for conversation management: clearing a conversation's history while
// keeping the agreement, and deleting a single message. Both are pure
// state + storage operations, exercised against a controller seeded with
// history (no networking needed).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/models/chat_message.dart';
import 'package:huddle/models/peer.dart';
import 'package:huddle/services/storage_service.dart';
import 'package:huddle/state/huddle_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final controllers = <HuddleController>[];

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    for (final c in controllers) {
      c.dispose();
    }
    controllers.clear();
  });

  ChatMessage msg(String id, bool mine, String text) => ChatMessage(
        id: id,
        peerId: 'p1',
        mine: mine,
        kind: MessageKind.text,
        sentAt: DateTime(2026, 1, 1, 9, int.parse(id.substring(1))),
        text: text,
      );

  Future<HuddleController> startWithHistory() async {
    final storage = StorageService(await SharedPreferences.getInstance());
    await storage.savePeers([
      Peer(id: 'p1', name: 'Phone', platform: 'android', pairedAt: DateTime(2026)),
    ]);
    await storage
        .saveMessages('p1', [msg('m1', true, 'first'), msg('m2', false, 'second'), msg('m3', true, 'third')]);
    final c = HuddleController();
    await c.init();
    controllers.add(c);
    return c;
  }

  test('clearConversation empties history but keeps the agreement', () async {
    final c = await startWithHistory();
    expect(c.conversation('p1'), hasLength(3));
    expect(c.isPaired('p1'), isTrue);

    await c.clearConversation('p1');

    expect(c.conversation('p1'), isEmpty);
    expect(c.isPaired('p1'), isTrue); // agreement preserved

    // Persisted: the history is gone but the peer remains.
    final reloaded = StorageService(await SharedPreferences.getInstance());
    expect(reloaded.loadMessages('p1'), isEmpty);
    expect(reloaded.loadPeers().map((p) => p.id), ['p1']);
  });

  test('deleteMessage removes one message and keeps the rest', () async {
    final c = await startWithHistory();

    expect(await c.deleteMessage('p1', 'm2'), isTrue);
    expect(c.conversation('p1').map((m) => m.id), ['m1', 'm3']);

    // Persisted.
    final reloaded = StorageService(await SharedPreferences.getInstance());
    expect(reloaded.loadMessages('p1').map((m) => m.id), ['m1', 'm3']);
  });

  test('deleteMessage is a no-op for an unknown message or peer', () async {
    final c = await startWithHistory();

    expect(await c.deleteMessage('p1', 'no-such'), isFalse);
    expect(await c.deleteMessage('absent', 'm1'), isFalse);
    expect(c.conversation('p1'), hasLength(3));
  });
}
