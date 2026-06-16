import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../models/peer.dart';

/// Persists paired peers, conversation history and received photo bytes.
class StorageService {
  StorageService(this._prefs);

  final SharedPreferences _prefs;

  static const _peersKey = 'huddle.peers';
  static String _msgsKey(String peerId) => 'huddle.msgs.$peerId';

  // --- Peers ---------------------------------------------------------------

  List<Peer> loadPeers() {
    final raw = _prefs.getString(_peersKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => Peer.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> savePeers(List<Peer> peers) async {
    final raw = jsonEncode(peers.map((p) => p.toJson()).toList());
    await _prefs.setString(_peersKey, raw);
  }

  // --- Conversations -------------------------------------------------------

  List<ChatMessage> loadMessages(String peerId) {
    final raw = _prefs.getString(_msgsKey(peerId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveMessages(String peerId, List<ChatMessage> messages) async {
    final raw = jsonEncode(messages.map((m) => m.toJson()).toList());
    await _prefs.setString(_msgsKey(peerId), raw);
  }

  Future<void> deleteConversation(String peerId) async {
    await _prefs.remove(_msgsKey(peerId));
  }

  // --- Media ---------------------------------------------------------------

  /// Writes received [bytes] to the app's media directory and returns the
  /// absolute path of the stored file.
  Future<String> saveIncomingPhoto(String fileName, List<int> bytes) async {
    final dir = await _mediaDir();
    final safe = fileName.replaceAll(RegExp(r'[^\w\-. ]'), '_');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/${stamp}_$safe');
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<Directory> _mediaDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/huddle_media');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
