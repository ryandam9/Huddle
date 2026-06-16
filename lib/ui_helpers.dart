import 'package:flutter/material.dart';

/// Returns a representative icon for a reported [platform] string.
IconData platformIcon(String platform) {
  switch (platform) {
    case 'android':
      return Icons.android;
    case 'ios':
    case 'macos':
      return Icons.apple;
    case 'windows':
      return Icons.window;
    case 'linux':
      return Icons.computer;
    default:
      return Icons.devices_other;
  }
}

/// Compact, locale-agnostic clock formatting (HH:mm) for message timestamps.
String formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

/// A friendly relative description like "just now" / "3m ago".
String formatRelative(DateTime t) {
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 45) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

/// Deterministic accent colour derived from an id, used for avatars.
Color colorForId(String id) {
  final hash = id.codeUnits.fold<int>(0, (a, c) => (a * 31 + c) & 0x7fffffff);
  const palette = [
    Color(0xFF5C6BC0),
    Color(0xFF26A69A),
    Color(0xFFEF5350),
    Color(0xFFAB47BC),
    Color(0xFF42A5F5),
    Color(0xFFFFA726),
    Color(0xFF66BB6A),
    Color(0xFFEC407A),
  ];
  return palette[hash % palette.length];
}
