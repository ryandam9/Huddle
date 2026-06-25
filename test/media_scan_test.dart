// Tests for listImageFiles: the non-recursive image scan that feeds the
// desktop "send a folder" batch.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:huddle/services/media_scan.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('huddle_scan_'));
  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  void touch(String relativePath) =>
      File('${dir.path}/$relativePath').writeAsStringSync('x');

  List<String> names(List<String> paths) =>
      [for (final p in paths) p.split(Platform.pathSeparator).last];

  test('returns only image files, sorted by path', () async {
    touch('b.jpg');
    touch('a.png');
    touch('notes.txt');
    touch('archive.zip');

    expect(names(await listImageFiles(dir.path)), ['a.png', 'b.jpg']);
  });

  test('matches extensions case-insensitively', () async {
    touch('PHOTO.JPG');
    touch('Other.PNG');
    touch('clip.HEIC');

    final found = names(await listImageFiles(dir.path));
    expect(found, containsAll(['PHOTO.JPG', 'Other.PNG', 'clip.HEIC']));
    expect(found, hasLength(3));
  });

  test('skips dotfiles, extensionless files and subdirectories', () async {
    touch('good.gif');
    touch('.hidden'); // a dotfile, not a real extension
    touch('README'); // no extension
    Directory('${dir.path}/sub').createSync();
    touch('sub/nested.png'); // inside a subdirectory → not recursed into

    expect(names(await listImageFiles(dir.path)), ['good.gif']);
  });

  test('a missing directory yields an empty list', () async {
    expect(await listImageFiles('${dir.path}/does-not-exist'), isEmpty);
  });

  test('an empty directory yields an empty list', () async {
    expect(await listImageFiles(dir.path), isEmpty);
  });

  test('returns absolute paths that exist', () async {
    touch('pic.webp');
    final found = await listImageFiles(dir.path);
    expect(found, hasLength(1));
    expect(found.single, startsWith(dir.path));
    expect(File(found.single).existsSync(), isTrue);
  });
}
