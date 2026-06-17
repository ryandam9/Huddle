import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../responsive.dart';
import '../services/pairing.dart';
import '../services/protocol.dart';
import '../state/huddle_controller.dart';
import 'dashboard_screen.dart';
import 'messages_screen.dart';
import 'settings_screen.dart';

/// Top-level responsive shell: a bottom navigation bar on phones and a side
/// navigation rail on tablets/desktop. Also wires the pairing prompt + notices.
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final pages = const [
      DashboardScreen(),
      MessagesScreen(),
      SettingsScreen(),
    ];

    final destinations = <_Destination>[
      const _Destination(Icons.wifi_tethering_outlined, Icons.wifi_tethering,
          'Devices'),
      _Destination(Icons.forum_outlined, Icons.forum, 'Huddles',
          badge: controller.totalUnread),
      const _Destination(Icons.settings_outlined, Icons.settings, 'Settings'),
    ];

    if (context.isCompact) {
      return Scaffold(
        body: pages[_index],
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final d in destinations)
              NavigationDestination(
                icon: _badged(d.icon, d.badge),
                selectedIcon: _badged(d.selectedIcon, d.badge),
                label: d.label,
              ),
          ],
        ),
      );
    }

    // Tablet / desktop: navigation rail beside the content.
    final extended = context.isLargeWidth;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            minWidth: 76,
            minExtendedWidth: 200,
            selectedIndex: _index,
            onDestinationSelected: (i) => setState(() => _index = i),
            leading: Padding(
              padding: EdgeInsets.symmetric(
                  vertical: 16, horizontal: extended ? 8 : 0),
              child: _BrandMark(extended: extended),
            ),
            labelType: extended
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            destinations: [
              for (final d in destinations)
                NavigationRailDestination(
                  icon: _badged(d.icon, d.badge),
                  selectedIcon: _badged(d.selectedIcon, d.badge),
                  label: Text(d.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: pages[_index]),
        ],
      ),
    );
  }

  Widget _badged(IconData icon, int badge) {
    if (badge <= 0) return Icon(icon);
    return Badge(label: Text('$badge'), child: Icon(icon));
  }
}

class _Destination {
  const _Destination(this.icon, this.selectedIcon, this.label,
      {this.badge = 0});
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
}

/// Wordmark shown at the top of the navigation rail.
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.extended});
  final bool extended;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final logo = Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.primary, scheme.tertiary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Icon(Icons.groups_rounded, color: Colors.white, size: 24),
    );

    if (!extended) return logo;
    return Row(
      children: [
        logo,
        const SizedBox(width: 12),
        Text('Huddle',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}
