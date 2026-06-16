// Tests for the persistent device identity.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/services/identity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('creates a non-empty id and default name on first run', () async {
    final prefs = await SharedPreferences.getInstance();
    final identity = await Identity.loadOrCreate(prefs);

    expect(identity.id, isNotEmpty);
    expect(identity.name, isNotEmpty);
    expect(identity.platform, isNotEmpty);
  });

  test('reuses the same id across loads (persisted)', () async {
    final prefs = await SharedPreferences.getInstance();
    final first = await Identity.loadOrCreate(prefs);
    final second = await Identity.loadOrCreate(prefs);

    expect(second.id, first.id);
  });

  test('rename updates the name and persists it', () async {
    final prefs = await SharedPreferences.getInstance();
    final identity = await Identity.loadOrCreate(prefs);

    await identity.rename(prefs, 'My Device');
    expect(identity.name, 'My Device');

    final reloaded = await Identity.loadOrCreate(prefs);
    expect(reloaded.name, 'My Device');
  });

  test('rename ignores blank input', () async {
    final prefs = await SharedPreferences.getInstance();
    final identity = await Identity.loadOrCreate(prefs);
    final before = identity.name;

    await identity.rename(prefs, '   ');
    expect(identity.name, before);
  });
}
