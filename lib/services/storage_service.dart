import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/peer.dart';
import 'protocol.dart';

/// Persists paired peers, network/download settings and received photo bytes.
/// Conversation history lives in the database (see MessageStore).
class StorageService {
  StorageService(this._prefs) {
    _customDownloadDir = loadCustomDownloadDir();
  }

  final SharedPreferences _prefs;

  /// In-memory copy of the user's chosen download folder (null = default).
  /// Kept here so [saveIncomingPhoto] doesn't have to hit prefs per file.
  String? _customDownloadDir;
  set customDownloadDir(String? path) {
    final v = path?.trim();
    _customDownloadDir = (v == null || v.isEmpty) ? null : v;
  }

  static const _peersKey = 'huddle.peers';
  static const _broadcastKey = 'huddle.net.broadcast';
  static const _portKey = 'huddle.net.port';
  static const _downloadDirKey = 'huddle.media.dir';
  static const _notifyKey = 'huddle.media.notify';

  // --- Network settings ----------------------------------------------------

  String? loadCustomBroadcast() {
    final v = _prefs.getString(_broadcastKey)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> saveCustomBroadcast(String? address) async {
    final v = address?.trim();
    if (v == null || v.isEmpty) {
      await _prefs.remove(_broadcastKey);
    } else {
      await _prefs.setString(_broadcastKey, v);
    }
  }

  int loadDiscoveryPort() => _prefs.getInt(_portKey) ?? kDiscoveryPort;

  Future<void> saveDiscoveryPort(int port) =>
      _prefs.setInt(_portKey, port);

  // --- Download settings ---------------------------------------------------

  /// A user-chosen folder for received files, or null to use the default
  /// app folder. Mostly useful on desktop where users expect a real folder
  /// (e.g. their Downloads directory).
  String? loadCustomDownloadDir() {
    final v = _prefs.getString(_downloadDirKey)?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  Future<void> saveCustomDownloadDir(String? path) async {
    final v = path?.trim();
    if (v == null || v.isEmpty) {
      await _prefs.remove(_downloadDirKey);
    } else {
      await _prefs.setString(_downloadDirKey, v);
    }
  }

  /// Whether to surface an in-app notification when content is received.
  /// Defaults to on so the user is aware of incoming files and messages.
  bool loadNotifyOnReceive() => _prefs.getBool(_notifyKey) ?? true;

  Future<void> saveNotifyOnReceive(bool enabled) =>
      _prefs.setBool(_notifyKey, enabled);

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

  // Conversation history now lives in the database (see MessageStore); it is no
  // longer serialised into shared_preferences.

  // --- Media ---------------------------------------------------------------

  /// Writes received [bytes] to the download folder and returns the absolute
  /// path of the stored file.
  ///
  /// If the chosen folder can't be written to — a custom folder that has been
  /// moved or deleted, or (on a sandboxed macOS build) a folder grant that
  /// didn't survive an app relaunch — it falls back to the default container
  /// folder so an incoming file is never silently lost.
  Future<String> saveIncomingPhoto(String fileName, List<int> bytes) async {
    final safe = fileName.replaceAll(RegExp(r'[^\w\-. ]'), '_');
    final stamp = DateTime.now().millisecondsSinceEpoch;
    // A short unique segment avoids collisions when two files share a name and
    // land in the same millisecond (e.g. a fast batch).
    final unique = const Uuid().v4().substring(0, 8);
    final leaf = '${stamp}_${unique}_$safe';
    try {
      final dir = await _mediaDir();
      return _writeBytes('${dir.path}/$leaf', bytes);
    } catch (_) {
      // Only the custom folder can fail this way; if there is none the default
      // folder failed and there's nowhere left to fall back to.
      if (_customDownloadDir == null) rethrow;
      final dir = await _defaultMediaDir();
      return _writeBytes('${dir.path}/$leaf', bytes);
    }
  }

  Future<String> _writeBytes(String path, List<int> bytes) async {
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Absolute path of the folder where received files are (or would be)
  /// stored, honouring a user-chosen folder when set. Safe to call for
  /// display: it resolves the path but does not require the folder to exist.
  Future<String> resolveMediaPath() async {
    if (_customDownloadDir != null) return _customDownloadDir!;
    return _defaultMediaPath();
  }

  /// Deletes a stored media [path] when (and only when) it lives inside the
  /// app's own default media folder, so removing a message cleans up the copy
  /// Huddle saved but never reaches into a custom download folder the user
  /// manages themselves — files they redirected there are considered theirs to
  /// keep. Best-effort: a missing file or an I/O error is ignored.
  Future<void> deleteManagedMedia(String path) async {
    try {
      final managed = await _defaultMediaPath();
      // Only inside our own folder — leave the user's chosen folder untouched.
      if (path != managed && !path.startsWith('$managed/')) return;
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Cleanup is best-effort and must never surface to the caller.
    }
  }

  /// The app's own media folder inside its container — always writable, even
  /// under the macOS sandbox, so it doubles as the fallback location.
  Future<String> _defaultMediaPath() async {
    final base = await getApplicationDocumentsDirectory();
    return '${base.path}/huddle_media';
  }

  /// Checks that [path] can be used as a download folder by ensuring it can
  /// be created/written. Returns true on success.
  Future<bool> canUseDownloadDir(String path) async {
    try {
      final dir = Directory(path.trim());
      if (!await dir.exists()) await dir.create(recursive: true);
      // Confirm we can actually write into it.
      final probe = File('${dir.path}/.huddle_write_test');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<Directory> _mediaDir() async => _ensureDir(await resolveMediaPath());

  Future<Directory> _defaultMediaDir() async =>
      _ensureDir(await _defaultMediaPath());

  Future<Directory> _ensureDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
