// Tests for the small pure UI helpers. These need no plugins or network.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/services/storage_service.dart';
import 'package:huddle/ui_helpers.dart';

void main() {
  group('formatTime', () {
    test('zero-pads hours and minutes', () {
      expect(formatTime(DateTime(2024, 1, 1, 9, 5)), '09:05');
    });

    test('handles midnight and noon', () {
      expect(formatTime(DateTime(2024, 1, 1, 0, 0)), '00:00');
      expect(formatTime(DateTime(2024, 1, 1, 12, 0)), '12:00');
      expect(formatTime(DateTime(2024, 1, 1, 23, 59)), '23:59');
    });
  });

  group('formatRelative', () {
    test('recent times read as "just now"', () {
      expect(formatRelative(DateTime.now()), 'just now');
    });

    test('minutes, hours and days are summarised', () {
      final now = DateTime.now();
      expect(formatRelative(now.subtract(const Duration(minutes: 5))), '5m ago');
      expect(formatRelative(now.subtract(const Duration(hours: 3))), '3h ago');
      expect(formatRelative(now.subtract(const Duration(days: 2))), '2d ago');
    });

    test('rolls over cleanly at the unit boundaries', () {
      final now = DateTime.now();
      expect(
          formatRelative(now.subtract(const Duration(seconds: 44))), 'just now');
      expect(
          formatRelative(now.subtract(const Duration(minutes: 59))), '59m ago');
      expect(formatRelative(now.subtract(const Duration(minutes: 60))), '1h ago');
      expect(formatRelative(now.subtract(const Duration(hours: 23))), '23h ago');
      expect(formatRelative(now.subtract(const Duration(hours: 24))), '1d ago');
    });
  });

  group('platformIcon', () {
    test('maps known platforms', () {
      expect(platformIcon('android'), Icons.android);
      expect(platformIcon('ios'), Icons.apple);
      expect(platformIcon('macos'), Icons.apple);
      expect(platformIcon('windows'), Icons.window);
      expect(platformIcon('linux'), Icons.computer);
    });

    test('falls back for unknown platforms', () {
      expect(platformIcon('toaster'), Icons.devices_other);
      expect(platformIcon(''), Icons.devices_other);
    });
  });

  group('StorageService download settings', () {
    test('notifications default to on and persist when toggled', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      expect(storage.loadNotifyOnReceive(), isTrue);
      await storage.saveNotifyOnReceive(false);
      expect(storage.loadNotifyOnReceive(), isFalse);
    });

    test('custom download folder round-trips and clears', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      expect(storage.loadCustomDownloadDir(), isNull);
      await storage.saveCustomDownloadDir('/tmp/huddle-test');
      expect(storage.loadCustomDownloadDir(), '/tmp/huddle-test');

      await storage.saveCustomDownloadDir('   ');
      expect(storage.loadCustomDownloadDir(), isNull);
    });

    test('resolveMediaPath honours a custom folder', () async {
      SharedPreferences.setMockInitialValues(
          {'huddle.media.dir': '/tmp/huddle-custom'});
      final prefs = await SharedPreferences.getInstance();
      final storage = StorageService(prefs);

      expect(await storage.resolveMediaPath(), '/tmp/huddle-custom');
    });
  });

  group('colorForId', () {
    test('is deterministic for the same id', () {
      expect(colorForId('abc'), colorForId('abc'));
    });

    test('always returns a colour from the palette', () {
      for (final id in ['', 'a', 'long-uuid-like-value', '12345']) {
        // Should not throw and should produce a fully opaque colour.
        expect(colorForId(id).a, 1.0);
      }
    });
  });
}
