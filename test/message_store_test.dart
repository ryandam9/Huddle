// Tests for MessageStore: the per-message database backing conversation history
// (one record per message, with targeted status updates) plus per-peer unread /
// read-receipt meta, and the one-time import from the old shared_preferences
// format. A fresh in-memory database is used per test for isolation.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/models/chat_message.dart';
import 'package:huddle/services/message_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MessageStore store;

  setUp(() async {
    final db = await newDatabaseFactoryMemory().openDatabase('huddle.db');
    store = MessageStore(db);
  });

  ChatMessage msg(
    String id,
    String peerId, {
    bool mine = true,
    int sentAt = 0,
    MessageStatus status = MessageStatus.sending,
  }) =>
      ChatMessage(
        id: id,
        peerId: peerId,
        mine: mine,
        kind: MessageKind.text,
        sentAt: DateTime.fromMillisecondsSinceEpoch(sentAt),
        text: id,
        status: status,
      );

  group('messages', () {
    test('appends and reads back oldest-first, filtered by peer', () async {
      await store.append(msg('m2', 'p1', sentAt: 20));
      await store.append(msg('m1', 'p1', sentAt: 10));
      await store.append(msg('x', 'p2', sentAt: 15));

      final p1 = await store.messagesFor('p1');
      expect(p1.map((m) => m.id), ['m1', 'm2']); // sorted by sentAt
      expect(await store.messagesFor('p2'), hasLength(1));
      expect(await store.messagesFor('absent'), isEmpty);
    });

    test('append round-trips every field', () async {
      await store.append(ChatMessage(
        id: 'ph',
        peerId: 'p1',
        mine: false,
        kind: MessageKind.photo,
        sentAt: DateTime.fromMillisecondsSinceEpoch(99),
        filePath: '/tmp/a.png',
        fileName: 'a.png',
        status: MessageStatus.read,
      ));

      final got = (await store.messagesFor('p1')).single;
      expect(got.kind, MessageKind.photo);
      expect(got.mine, isFalse);
      expect(got.filePath, '/tmp/a.png');
      expect(got.fileName, 'a.png');
      expect(got.status, MessageStatus.read);
      expect(got.sentAt.millisecondsSinceEpoch, 99);
    });

    test('updateStatus changes one message in place', () async {
      await store.append(msg('m1', 'p1', status: MessageStatus.sending));
      await store.updateStatus('m1', MessageStatus.delivered);

      expect((await store.messagesFor('p1')).single.status,
          MessageStatus.delivered);
    });

    test('updateStatus on a missing id is a harmless no-op', () async {
      await store.updateStatus('ghost', MessageStatus.read); // must not throw
      expect(await store.messagesFor('p1'), isEmpty);
    });

    test('deleteMessage removes one and reports whether it existed', () async {
      await store.append(msg('m1', 'p1'));
      await store.append(msg('m2', 'p1'));

      expect(await store.deleteMessage('m1'), isTrue);
      expect(await store.deleteMessage('m1'), isFalse); // already gone
      expect((await store.messagesFor('p1')).map((m) => m.id), ['m2']);
    });

    test("deleteConversation clears one peer's messages and meta only",
        () async {
      await store.append(msg('m1', 'p1'));
      await store.append(msg('k1', 'p2'));
      await store.saveMeta('p1', unread: 3, unacked: ['m1']);
      await store.saveMeta('p2', unread: 1, unacked: []);

      await store.deleteConversation('p1');

      expect(await store.messagesFor('p1'), isEmpty);
      expect(await store.messagesFor('p2'), hasLength(1)); // other peer kept
      final meta = await store.loadMeta();
      expect(meta.containsKey('p1'), isFalse);
      expect(meta['p2']!.unread, 1);
    });
  });

  group('meta', () {
    test('saveMeta / loadMeta round-trips unread and unacked', () async {
      await store.saveMeta('p1', unread: 2, unacked: ['a', 'b']);
      await store.saveMeta('p2', unread: 0, unacked: []);

      final meta = await store.loadMeta();
      expect(meta['p1']!.unread, 2);
      expect(meta['p1']!.unacked, ['a', 'b']);
      expect(meta['p2']!.unread, 0);
      expect(meta['p2']!.unacked, isEmpty);
    });

    test("saveMeta overwrites a peer's previous meta", () async {
      await store.saveMeta('p1', unread: 5, unacked: ['x']);
      await store.saveMeta('p1', unread: 0, unacked: []);

      final meta = await store.loadMeta();
      expect(meta['p1']!.unread, 0);
      expect(meta['p1']!.unacked, isEmpty);
    });

    test('loadMeta starts empty', () async {
      expect(await store.loadMeta(), isEmpty);
    });
  });

  group('migration from shared_preferences', () {
    test('imports old conversations, then removes the old keys', () async {
      final p1 = [
        msg('m1', 'p1', sentAt: 10).toJson(),
        msg('m2', 'p1', sentAt: 20).toJson(),
      ];
      SharedPreferences.setMockInitialValues({
        'huddle.msgs.p1': jsonEncode(p1),
        'huddle.msgs.p2': jsonEncode([msg('k1', 'p2').toJson()]),
        'unrelated.key': 'keep me',
      });
      final prefs = await SharedPreferences.getInstance();

      await store.migrateFromPrefs(prefs);

      expect((await store.messagesFor('p1')).map((m) => m.id), ['m1', 'm2']);
      expect(await store.messagesFor('p2'), hasLength(1));
      // Old conversation keys removed; flag set; unrelated keys untouched.
      expect(prefs.getString('huddle.msgs.p1'), isNull);
      expect(prefs.getString('huddle.msgs.p2'), isNull);
      expect(prefs.getBool('huddle.db.migrated'), isTrue);
      expect(prefs.getString('unrelated.key'), 'keep me');
    });

    test('is a no-op once the flag is set (does not re-import)', () async {
      SharedPreferences.setMockInitialValues({'huddle.db.migrated': true});
      final prefs = await SharedPreferences.getInstance();
      // A stray old key present after the flag was set must not be re-imported.
      await prefs.setString(
          'huddle.msgs.p1', jsonEncode([msg('m1', 'p1').toJson()]));

      await store.migrateFromPrefs(prefs);

      expect(await store.messagesFor('p1'), isEmpty);
      expect(prefs.getString('huddle.msgs.p1'), isNotNull); // left untouched
    });

    test('skips a corrupt conversation but still imports the good ones',
        () async {
      SharedPreferences.setMockInitialValues({
        'huddle.msgs.bad': '{not valid json',
        'huddle.msgs.good': jsonEncode([msg('g1', 'good').toJson()]),
      });
      final prefs = await SharedPreferences.getInstance();

      await store.migrateFromPrefs(prefs);

      expect(await store.messagesFor('good'), hasLength(1));
      expect(prefs.getString('huddle.msgs.bad'), isNull); // dropped regardless
      expect(prefs.getBool('huddle.db.migrated'), isTrue);
    });
  });
}
