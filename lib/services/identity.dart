import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// This device's own identity on the network: a stable id and a display name.
///
/// Both are persisted so the device keeps the same identity across restarts
/// (which is what lets pairing agreements survive).
class Identity {
  Identity({required this.id, required this.name, required this.platform});

  final String id;
  String name;
  final String platform;

  static const _idKey = 'huddle.identity.id';
  static const _nameKey = 'huddle.identity.name';

  /// Loads the existing identity or creates (and persists) a new one.
  static Future<Identity> loadOrCreate(SharedPreferences prefs) async {
    final platform = _detectPlatform();

    var id = prefs.getString(_idKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_idKey, id);
    }

    final name = prefs.getString(_nameKey) ?? _defaultName(platform);
    return Identity(id: id, name: name, platform: platform);
  }

  Future<void> rename(SharedPreferences prefs, String newName) async {
    name = newName.trim().isEmpty ? name : newName.trim();
    await prefs.setString(_nameKey, name);
  }

  static String _detectPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }

  static String _defaultName(String platform) {
    String host;
    try {
      host = Platform.localHostname;
    } catch (_) {
      host = '';
    }
    if (host.isNotEmpty) return host;
    // Fall back to a capitalised platform name.
    return platform.isEmpty
        ? 'My device'
        : '${platform[0].toUpperCase()}${platform.substring(1)} device';
  }
}
