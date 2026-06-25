// Widget tests for the UI: shared widgets, the device dashboard (including the
// pairing-code dialog interaction) and the conversations list. A fake
// controller supplies state so no network is involved.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:huddle/models/device.dart';
import 'package:huddle/models/peer.dart';
import 'package:huddle/models/chat_message.dart';
import 'package:huddle/services/identity.dart';
import 'package:huddle/state/huddle_controller.dart';
import 'package:huddle/screens/chat_screen.dart';
import 'package:huddle/screens/dashboard_screen.dart';
import 'package:huddle/screens/help_screen.dart';
import 'package:huddle/screens/messages_screen.dart';
import 'package:huddle/theme.dart';
import 'package:huddle/widgets/common.dart';
import 'package:huddle/widgets/scan_pulse.dart';

class FakeController extends HuddleController {
  FakeController({this.devicesList = const [], this.peersList = const []}) {
    identity = Identity(id: 'me', name: 'My Pixel', platform: 'android');
    ready = true;
    wifiIp = '192.168.1.42';
  }

  List<Device> devicesList;
  List<Peer> peersList;
  String? startedPairingFor;
  int refreshes = 0;

  @override
  void refreshDiscovery() => refreshes++;

  @override
  Future<void> init() async {}
  @override
  List<Device> get devices => devicesList;
  @override
  List<Peer> get peers => peersList;
  @override
  bool isPaired(String id) => peersList.any((p) => p.id == id);
  @override
  bool isOnline(String id) => true;
  @override
  List<ChatMessage> conversation(String id) => const [];
  @override
  int unreadFor(String id) => 0;
  @override
  int get totalUnread => 0;

  @override
  String startPairing(Device device) {
    startedPairingFor = device.id;
    outgoingPairing = OutgoingPairing(
        peerId: device.id, peerName: device.name, code: '424242');
    notifyListeners();
    return '424242';
  }

  @override
  void cancelPairing() {
    outgoingPairing = null;
    notifyListeners();
  }
}

Device _device(String id, String name, String platform) => Device(
    id: id,
    name: name,
    host: '192.168.1.9',
    port: 5000,
    platform: platform,
    lastSeen: DateTime.now());

Peer _peer(String id, String name) =>
    Peer(id: id, name: name, platform: 'ios', pairedAt: DateTime(2026));

void main() {
  Future<void> pumpApp(WidgetTester tester, FakeController c, Widget child,
      {Size size = const Size(400, 820)}) async {
    tester.view.devicePixelRatio = 2.0;
    tester.view.physicalSize = Size(size.width * 2, size.height * 2);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<HuddleController>.value(
        value: c,
        child: MaterialApp(theme: HuddleTheme.light(), home: child),
      ),
    );
    await tester.pump();
  }

  group('shared widgets', () {
    testWidgets('EmptyStateView shows its title and message', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: EmptyStateView(
              icon: Icons.radar, title: 'Nothing here', message: 'Come back'),
        ),
      ));
      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('Come back'), findsOneWidget);
      expect(find.byIcon(Icons.radar), findsOneWidget);
    });

    testWidgets('HuddleAvatar renders the platform glyph', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: HuddleAvatar(
              id: 'x', name: 'Phone', platform: 'android', showStatus: true),
        ),
      ));
      expect(find.byIcon(Icons.android), findsOneWidget);
    });

    testWidgets('RadarPulse renders its center glyph (and keeps animating)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Center(child: RadarPulse(icon: Icons.wifi_tethering)),
        ),
      ));
      // Don't pumpAndSettle: the pulse repeats forever by design.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byIcon(Icons.wifi_tethering), findsOneWidget);
    });
  });

  group('DashboardScreen', () {
    testWidgets('lists devices with Pair / Open actions', (tester) async {
      final c = FakeController(
        devicesList: [
          _device('d1', 'Office MacBook', 'macos'),
          _device('d2', 'Workshop Pi', 'linux'),
        ],
        peersList: [_peer('d2', 'Workshop Pi')],
      );
      await pumpApp(tester, c, const DashboardScreen());

      expect(find.text('Office MacBook'), findsOneWidget);
      expect(find.text('Workshop Pi'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Pair'), findsOneWidget);
      // The paired device exposes an Open action instead.
      expect(find.widgetWithText(FilledButton, 'Open'), findsOneWidget);
    });

    testWidgets('empty state appears when no devices are found',
        (tester) async {
      await pumpApp(tester, FakeController(), const DashboardScreen());
      expect(find.text('Looking for devices…'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Scan again'), findsOneWidget);
    });

    testWidgets('app-bar refresh triggers an on-demand scan', (tester) async {
      final c = FakeController(devicesList: [_device('d1', 'MacBook', 'macos')]);
      await pumpApp(tester, c, const DashboardScreen());

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pump();
      expect(c.refreshes, 1);
    });

    testWidgets('empty-state "Scan again" triggers a scan', (tester) async {
      final c = FakeController();
      await pumpApp(tester, c, const DashboardScreen());

      await tester.tap(find.widgetWithText(FilledButton, 'Scan again'));
      await tester.pump();
      expect(c.refreshes, 1);
    });

    testWidgets('tapping Pair starts pairing and shows the code dialog',
        (tester) async {
      final c = FakeController(devicesList: [_device('d1', 'MacBook', 'macos')]);
      await pumpApp(tester, c, const DashboardScreen());

      await tester.tap(find.widgetWithText(FilledButton, 'Pair'));
      await tester.pump(); // start dialog
      await tester.pump(const Duration(milliseconds: 50));

      expect(c.startedPairingFor, 'd1');
      // Code 424242 is rendered grouped as "424 242".
      expect(find.text('424 242'), findsOneWidget);
      expect(find.textContaining('Enter this code'), findsOneWidget);
    });
  });

  group('MessagesScreen', () {
    testWidgets('shows paired peers in the list', (tester) async {
      final c = FakeController(peersList: [
        _peer('p1', "Ravi's iPhone"),
        _peer('p2', 'Workshop Pi'),
      ]);
      await pumpApp(tester, c, const MessagesScreen());
      expect(find.text("Ravi's iPhone"), findsOneWidget);
      expect(find.text('Workshop Pi'), findsOneWidget);
    });

    testWidgets('shows an empty state with no huddles', (tester) async {
      await pumpApp(tester, FakeController(), const MessagesScreen());
      expect(find.text('No huddles yet'), findsOneWidget);
    });
  });

  group('HelpScreen', () {
    testWidgets('renders the intro and the main troubleshooting topic',
        (tester) async {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(400 * 2, 1000 * 2);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(theme: HuddleTheme.light(), home: const HelpScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Trouble connecting?'), findsOneWidget);
      expect(find.text("The other device isn't showing up"), findsOneWidget);
      // That topic is expanded by default, so its first step is visible.
      expect(find.textContaining('Put both devices on the same'),
          findsOneWidget);
    });

    testWidgets('expands a collapsed topic when tapped', (tester) async {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(400 * 2, 1000 * 2);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(theme: HuddleTheme.light(), home: const HelpScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('A 6'), findsNothing); // collapsed
      await tester.scrollUntilVisible(
          find.text('How do I connect two devices?'), 300);
      await tester.tap(find.text('How do I connect two devices?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('A 6'), findsWidgets); // now revealed
    });
  });

  group('ChatScreen options', () {
    testWidgets('the options menu offers clear and end; clear asks first',
        (tester) async {
      final c = FakeController(peersList: [_peer('p1', 'Phone')]);
      await pumpApp(tester, c, ChatScreen(peer: _peer('p1', 'Phone')));

      await tester.tap(find.byType(PopupMenuButton<String>));
      await tester.pumpAndSettle();
      expect(find.text('Clear messages'), findsOneWidget);
      expect(find.text('End huddle'), findsOneWidget);

      // Choosing "Clear messages" asks for confirmation rather than acting.
      await tester.tap(find.text('Clear messages'));
      await tester.pumpAndSettle();
      expect(find.text('Clear messages?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Clear messages?'), findsNothing);

      c.dispose();
    });
  });
}
