import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/protocol.dart';
import '../state/huddle_controller.dart';
import '../widgets/common.dart';
import 'help_screen.dart';

/// Identity, network info and active agreements. Content is centered and
/// width-constrained so it looks intentional on wide desktop windows.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();
    final identity = controller.identity;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _DeviceHeader(controller: controller),
              const SizedBox(height: 24),
              _SectionLabel('This device'),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: const Text('Display name'),
                      subtitle: Text(identity.name),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editName(context, controller),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.lan_outlined),
                      title: const Text('Network address'),
                      subtitle: Text(controller.wifiIp ?? 'Unknown'),
                    ),
                    const Divider(height: 1, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.fingerprint),
                      title: const Text('Device id'),
                      subtitle: Text(identity.id,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              _SectionLabel('Agreements (${controller.peers.length})'),
              Card(
                child: controller.peers.isEmpty
                    ? const ListTile(
                        leading: Icon(Icons.handshake_outlined),
                        title: Text('No paired devices'),
                        subtitle:
                            Text('Pair from the Devices tab to start sharing.'),
                      )
                    : Column(
                        children: [
                          for (var i = 0; i < controller.peers.length; i++) ...[
                            if (i > 0) const Divider(height: 1, indent: 72),
                            _PeerRow(controller: controller, index: i),
                          ],
                        ],
                      ),
              ),
              const SizedBox(height: 24),
              _SectionLabel('Support'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.support),
                  title: const Text('Help & troubleshooting'),
                  subtitle:
                      const Text("Devices not finding each other? Start here."),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const HelpScreen()),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _SectionLabel('Network (advanced)'),
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
                      subtitle:
                          Text(controller.customBroadcast ?? 'Automatic'),
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
                padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Text(
                  'These are for unusual networks. The defaults work for almost '
                  'everyone — only change them if discovery isn’t working and '
                  'you know what to enter.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(height: 24),
              _SectionLabel('About'),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Huddle'),
                  subtitle: const Text(
                    'Share messages and photos directly with devices on your '
                    'local network — no account, no internet required.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _editName(
      BuildContext context, HuddleController controller) async {
    final field = TextEditingController(text: controller.identity.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Display name'),
        content: TextField(
          controller: field,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'How others see you'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(field.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (newName != null && newName.trim().isNotEmpty) {
      await controller.renameSelf(newName);
    }
  }

  Future<void> _editPort(
      BuildContext context, HuddleController controller) async {
    final field =
        TextEditingController(text: '${controller.discoveryPort}');
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
                    setState(() => error = 'Enter a number between 1024 and '
                        '65535');
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
    // Sentinel distinguishes "cleared" from "cancelled".
    const cleared = ' ';
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

class _DeviceHeader extends StatelessWidget {
  const _DeviceHeader({required this.controller});
  final HuddleController controller;

  @override
  Widget build(BuildContext context) {
    final identity = controller.identity;
    return Row(
      children: [
        HuddleAvatar(
          id: identity.id,
          name: identity.name,
          platform: identity.platform,
          radius: 32,
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(identity.name,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('This device · ${identity.platform}',
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

class _PeerRow extends StatelessWidget {
  const _PeerRow({required this.controller, required this.index});
  final HuddleController controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final peer = controller.peers[index];
    final online = controller.isOnline(peer.id);
    return ListTile(
      leading: HuddleAvatar(
        id: peer.id,
        name: peer.name,
        platform: peer.platform,
        radius: 20,
        showStatus: true,
        online: online,
      ),
      title: Text(peer.name),
      subtitle: Text(online ? 'Online' : 'Offline'),
      trailing: IconButton(
        icon: const Icon(Icons.link_off),
        tooltip: 'End huddle',
        onPressed: () => controller.unpair(peer.id),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}
