import 'dart:convert';

import 'package:sembast/sembast.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';

/// Per-peer unread count and the ids of received messages not yet reported as
/// read (persisted so they survive a restart).
class MetaState {
  const MetaState({this.unread = 0, this.unacked = const []});
  final int unread;
  final List<String> unacked;
}

/// Conversation history backed by a local database.
///
/// Each message is one record keyed by its id, so appending a message or
/// updating its delivery status touches a single row — unlike the previous
/// approach, which re-serialised the entire conversation to a
/// `shared_preferences` string on every change. Per-peer unread / read-receipt
/// state lives in a small `meta` store alongside it.
class MessageStore {
  MessageStore(this._db);

  final Database _db;

  static final StoreRef<String, Map<String, Object?>> _messages =
      stringMapStoreFactory.store('messages');
  static final StoreRef<String, Map<String, Object?>> _meta =
      stringMapStoreFactory.store('meta');

  // --- Messages ------------------------------------------------------------

  Future<void> append(ChatMessage message) =>
      _messages.record(message.id).put(_db, message.toJson());

  /// All of [peerId]'s messages, oldest first.
  Future<List<ChatMessage>> messagesFor(String peerId) async {
    final records = await _messages.find(
      _db,
      finder: Finder(
        filter: Filter.equals('peerId', peerId),
        sortOrders: [SortOrder('sentAt')],
      ),
    );
    return [
      for (final r in records)
        ChatMessage.fromJson(Map<String, dynamic>.from(r.value)),
    ];
  }

  /// Updates just the delivery status of one message (no-op if it's gone).
  Future<void> updateStatus(String mid, MessageStatus status) =>
      _messages.record(mid).update(_db, {'status': status.name});

  Future<bool> deleteMessage(String mid) async =>
      (await _messages.record(mid).delete(_db)) != null;

  Future<void> deleteConversation(String peerId) async {
    await _messages.delete(
      _db,
      finder: Finder(filter: Filter.equals('peerId', peerId)),
    );
    await _meta.record(peerId).delete(_db);
  }

  // --- Per-peer meta -------------------------------------------------------

  Future<Map<String, MetaState>> loadMeta() async {
    final records = await _meta.find(_db);
    return {
      for (final r in records)
        r.key: MetaState(
          unread: (r.value['unread'] as int?) ?? 0,
          unacked: [
            for (final e in (r.value['unacked'] as List?) ?? const [])
              e as String,
          ],
        ),
    };
  }

  Future<void> saveMeta(String peerId,
          {required int unread, required List<String> unacked}) =>
      _meta.record(peerId).put(_db, {'unread': unread, 'unacked': unacked});

  // --- Migration -----------------------------------------------------------

  /// One-time import of conversations stored in the old `shared_preferences`
  /// format (`huddle.msgs.<peerId>` JSON strings) into the database, then
  /// removes the old keys. Safe to call on every launch.
  Future<void> migrateFromPrefs(SharedPreferences prefs) async {
    const flag = 'huddle.db.migrated';
    if (prefs.getBool(flag) ?? false) return;
    const prefix = 'huddle.msgs.';
    for (final key in prefs.getKeys().toList()) {
      if (!key.startsWith(prefix)) continue;
      final raw = prefs.getString(key);
      if (raw != null && raw.isNotEmpty) {
        try {
          final list = (jsonDecode(raw) as List)
              .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>));
          await _db.transaction((txn) async {
            for (final m in list) {
              await _messages.record(m.id).put(txn, m.toJson());
            }
          });
        } catch (_) {
          // Skip a corrupt conversation rather than abort the whole migration.
        }
      }
      await prefs.remove(key);
    }
    await prefs.setBool(flag, true);
  }
}
