import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/pairing.dart';
import '../services/protocol.dart';
import '../state/huddle_controller.dart';
import '../ui_helpers.dart';
import 'dashboard_screen.dart';
import 'huddles_screen.dart';
import 'settings_screen.dart';

/// Top-level shell hosting the three sections of the app and wiring the
/// incoming-pairing prompt to a dialog.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Register the pairing handlers once the controller is available.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<HuddleController>();
      controller.onPairRequest = _promptPairRequest;
      controller.onNotice = _showNotice;
    });
  }

  void _showNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Prompts the user to type the code shown on the requesting device. Returns
  /// the entered code, or null if they decline.
  Future<String?> _promptPairRequest(Endpoint from) async {
    if (!mounted) return null;
    final field = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pairing request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '"${from.name}" (${from.platform}) wants to huddle.\n\n'
              'Enter the code shown on their screen to confirm:',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: field,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: kPairingCodeLength,
              style: const TextStyle(fontSize: 24, letterSpacing: 6),
              decoration: const InputDecoration(
                counterText: '',
                hintText: '••••••',
              ),
              onSubmitted: (v) => Navigator.of(ctx).pop(v),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Decline'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(field.text),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return (code == null || code.trim().isEmpty) ? null : code.trim();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();

    if (!controller.ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final pages = const [
      DashboardScreen(),
      HuddlesScreen(),
      SettingsScreen(),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.wifi_tethering),
            label: 'Devices',
          ),
          NavigationDestination(
            icon: _HuddlesIcon(count: controller.totalUnread),
            label: 'Huddles',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

/// Huddles tab icon with an unread badge.
class _HuddlesIcon extends StatelessWidget {
  const _HuddlesIcon({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const Icon(Icons.forum_outlined);
    return Badge(
      label: Text('$count'),
      child: const Icon(Icons.forum),
    );
  }
}

/// Small reusable avatar used across screens.
class HuddleAvatar extends StatelessWidget {
  const HuddleAvatar({
    super.key,
    required this.id,
    required this.name,
    required this.platform,
    this.radius = 22,
  });

  final String id;
  final String name;
  final String platform;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: colorForId(id),
      child: Icon(platformIcon(platform), color: Colors.white, size: radius),
    );
  }
}
