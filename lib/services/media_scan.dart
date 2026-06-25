import 'dart:io';

/// File extensions Huddle treats as shareable images.
const _imageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.heic',
  '.bmp',
};

/// Returns the absolute paths of image files directly inside [dirPath], sorted
/// by path. The scan is non-recursive (subdirectories are skipped) and
/// resilient: a missing directory, non-image files and unreadable entries all
/// just yield nothing rather than throwing — handy for feeding a batch send
/// from a user-picked folder on desktop.
Future<List<String>> listImageFiles(String dirPath) async {
  final dir = Directory(dirPath);
  if (!await dir.exists()) return const [];

  final paths = <String>[];
  try {
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      if (_isImage(entity.path)) paths.add(entity.path);
    }
  } on FileSystemException {
    // Unreadable directory — return whatever we managed to collect.
  }
  paths.sort();
  return paths;
}

bool _isImage(String path) {
  final name = path.split(Platform.pathSeparator).last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0) return false; // no extension, or a dotfile like ".hidden"
  return _imageExtensions.contains(name.substring(dot).toLowerCase());
}
