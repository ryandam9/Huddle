// Widget tests for the Downloads section of the Settings screen: the save
// location is shown, the edit dialog updates it, and the notifications toggle
// flips the controller flag. Backed by a real HuddleController over mocked
// SharedPreferences; a custom download folder is seeded so path resolution
// doesn't need the path_provider plugin.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:huddle/screens/settings_screen.dart';
import 'package:huddle/state/huddle_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tempDirs = <Directory>[];

  Directory makeTempDir() {
    final dir = Directory.systemTemp.createTempSync('huddle_dl_');
    tempDirs.add(dir);
    return dir;
  }

  Future<HuddleController> startWith(String downloadDir) async {
    SharedPreferences.setMockInitialValues({'huddle.media.dir': downloadDir});
    final c = HuddleController();
    await c.init();
    return c;
  }

  Future<void> pumpSettings(WidgetTester tester, HuddleController c) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<HuddleController>.value(
        value: c,
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pump();
  }

  // Disposed inside each test (cancels the controller's networking timers)
  // because testWidgets checks for pending timers before tearDown runs. The
  // .value provider never owns/disposes the controller, so there's no
  // double-dispose. tearDown only clears the temp folders.
  tearDown(() {
    for (final d in tempDirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    tempDirs.clear();
  });

  testWidgets('shows the current download location and notifications toggle',
      (tester) async {
    final dir = makeTempDir();
    final c = await startWith(dir.path);
    await pumpSettings(tester, c);

    // Location is surfaced in the Downloads section.
    expect(find.text('Save received files to'), findsOneWidget);
    expect(find.text(dir.path), findsOneWidget);

    // Notifications toggle is present and on by default.
    expect(find.text('Notify on new files & messages'), findsOneWidget);
    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.value, isTrue);

    c.dispose();
  });

  testWidgets('toggling notifications updates the controller', (tester) async {
    final dir = makeTempDir();
    final c = await startWith(dir.path);
    await pumpSettings(tester, c);

    expect(c.notifyOnReceive, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(c.notifyOnReceive, isFalse);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    c.dispose();
  });

  testWidgets('tapping the location opens the edit dialog prefilled',
      (tester) async {
    final dir = makeTempDir();
    final c = await startWith(dir.path);
    await pumpSettings(tester, c);

    // Open the edit dialog from the location row.
    await tester.tap(find.text('Save received files to'));
    await tester.pumpAndSettle();

    // Dialog with its actions and the current folder prefilled into the field.
    expect(find.text('Download folder'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Use default'), findsOneWidget);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, dir.path);

    // Dismiss without committing IO (the save path is covered at the
    // controller level, where real async/IO can complete).
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Download folder'), findsNothing);

    c.dispose();
  });
}
