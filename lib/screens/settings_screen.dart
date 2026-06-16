import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/huddle_controller.dart';
import '../ui_helpers.dart';

/// Lets the user set their display name and review their identity and the
/// active agreements.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();
    final identity = controller.identity;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('This device'),
          ListTile(
            leading: Icon(platformIcon(identity.platform)),
            title: const Text('Display name'),
            subtitle: Text(identity.name),
            trailing: const Icon(Icons.edit),
            onTap: () => _editName(context, controller),
          ),
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Device id'),
            subtitle: Text(identity.id),
          ),
          ListTile(
            leading: const Icon(Icons.lan),
            title: const Text('Network address'),
            subtitle: Text(controller.wifiIp ?? 'Unknown'),
          ),
          const Divider(),
          _SectionHeader('Agreements (${controller.peers.length})'),
          if (controller.peers.isEmpty)
            const ListTile(
              leading: Icon(Icons.handshake_outlined),
              title: Text('No paired devices'),
              subtitle: Text('Pair from the Devices tab to start sharing.'),
            )
          else
            ...controller.peers.map(
              (p) => ListTile(
                leading: Icon(platformIcon(p.platform)),
                title: Text(p.name),
                subtitle: Text(
                  controller.isOnline(p.id) ? 'online' : 'offline',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.link_off),
                  tooltip: 'End huddle',
                  onPressed: () => controller.unpair(p.id),
                ),
              ),
            ),
          const Divider(),
          const _SectionHeader('About'),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('Huddle'),
            subtitle: Text(
              'Share messages and photos directly with devices on your local '
              'network — no account, no internet required.',
            ),
          ),
        ],
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
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
