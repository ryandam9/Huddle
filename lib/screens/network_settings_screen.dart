import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/protocol.dart';
import '../state/huddle_controller.dart';

/// Advanced network settings and diagnostics, on their own page so the main
/// Settings screen stays short. Most users never need to open this.
class NetworkSettingsScreen extends StatelessWidget {
  const NetworkSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();

    return Scaffold(
      appBar: AppBar(title: const Text('Network')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.router_outlined),
                      title: const Text('Your address'),
                      subtitle: Text(controller.wifiIp ?? 'Unknown'),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.settings_ethernet),
                      title: const Text('Discovery port'),
                      subtitle: Text('${controller.discoveryPort} · '
                          'must match on every device'),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editPort(context, controller),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.cell_tower),
                      title: const Text('Custom broadcast address'),
                      subtitle: Text(controller.customBroadcast ?? 'Automatic'),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editBroadcast(context, controller),
                    ),
                    const Divider(height: 1, indent: 56),
                    FutureBuilder<List<String>>(
                      future: controller.broadcastTargets(),
                      builder: (context, snapshot) {
                        final targets = snapshot.data ?? const [];
                        return ListTile(
                          leading: const Icon(Icons.podcasts),
                          title: const Text('Broadcasting to'),
                          subtitle: Text(targets.isEmpty
                              ? 'Calculating…'
                              : targets.join(', ')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(8, 12, 8, 0),
                child: Text(
                  'These are for unusual networks. The defaults work for almost '
                  'everyone — only change them if discovery isn’t working and '
                  'you know what to enter.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editPort(
      BuildContext context, HuddleController controller) async {
    final field = TextEditingController(text: '${controller.discoveryPort}');
    final port = await showDialog<int>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Discovery port'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The port devices use to find each other. It must be the '
                  'same on every device, or they won’t see each other. Leave '
                  'the default ($kDiscoveryPort) unless you really need to '
                  'change it.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: field,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Port (1024–65535)',
                    errorText: error,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(kDiscoveryPort),
                child: const Text('Reset'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final p = int.tryParse(field.text.trim());
                  if (p == null || p < 1024 || p > 65535) {
                    setState(() =>
                        error = 'Enter a number between 1024 and 65535');
                    return;
                  }
                  Navigator.of(ctx).pop(p);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (port != null) await controller.setDiscoveryPort(port);
  }

  Future<void> _editBroadcast(
      BuildContext context, HuddleController controller) async {
    final field =
        TextEditingController(text: controller.customBroadcast ?? '');
    const cleared = ' '; // sentinel: distinguishes "cleared" from "cancelled"
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Custom broadcast address'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'For unusual networks only. Huddle normally figures this out '
                  'automatically. If discovery isn’t working, you can add a '
                  'broadcast address here (for example 192.168.0.255).',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: field,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Broadcast address',
                    hintText: '192.168.0.255',
                    errorText: error,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(cleared),
                child: const Text('Use automatic'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final v = field.text.trim();
                  final ip = InternetAddress.tryParse(v);
                  if (ip == null || ip.type != InternetAddressType.IPv4) {
                    setState(() => error = 'Enter a valid IPv4 address');
                    return;
                  }
                  Navigator.of(ctx).pop(v);
                },
                child: const Text('Save'),
              ),
            ],
          ),
        );
      },
    );
    if (result == cleared) {
      await controller.setCustomBroadcast(null);
    } else if (result != null) {
      await controller.setCustomBroadcast(result);
    }
  }
}
