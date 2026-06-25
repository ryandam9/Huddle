import 'package:file_selector/file_selector.dart' show getDirectoryPath;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../responsive.dart';
import '../state/huddle_controller.dart';
import '../widgets/common.dart';
import 'chat_screen.dart' show confirmEndHuddle;
import 'help_screen.dart';
import 'network_settings_screen.dart';

/// Identity, agreements and links to sub-pages. On phones it's a single
/// column; on wide desktop windows the cards flow into two columns to use the
/// space and cut down on scrolling.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();

    final thisDevice = _Section(
      label: 'This device',
      child: Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.badge_outlined),
              title: const Text('Display name'),
              subtitle: Text(controller.identity.name),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editName(context, controller),
            ),
            const Divider(height: 1, indent: 56),
            ListTile(
              leading: const Icon(Icons.fingerprint),
              title: const Text('Device id'),
              subtitle: Text(controller.identity.id,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );

    final agreements = _Section(
      label: 'Agreements (${controller.peers.length})',
      child: Card(
        child: controller.peers.isEmpty
            ? const ListTile(
                leading: Icon(Icons.handshake_outlined),
                title: Text('No paired devices'),
                subtitle: Text('Pair from the Devices tab to start sharing.'),
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
    );

    final network = _Section(
      label: 'Network',
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.lan_outlined),
          title: const Text('Network & diagnostics'),
          subtitle: const Text('Ports, broadcast address, your IP'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const NetworkSettingsScreen()),
          ),
        ),
      ),
    );

    final downloads = _Section(
      label: 'Downloads',
      child: Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Save received files to'),
              subtitle: Text(
                controller.downloadLocation ?? 'Resolving…',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.edit_outlined),
              onTap: () => _editDownloadDir(context, controller),
            ),
            const Divider(height: 1, indent: 56),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Notify on new files & messages'),
              subtitle: const Text(
                  'Show an alert when something is received or saved'),
              value: controller.notifyOnReceive,
              onChanged: (v) => controller.setNotifyOnReceive(v),
            ),
          ],
        ),
      ),
    );

    final support = _Section(
      label: 'Support',
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.support),
          title: const Text('Help & troubleshooting'),
          subtitle: const Text("Devices not finding each other? Start here."),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HelpScreen()),
          ),
        ),
      ),
    );

    const about = _Section(
      label: 'About',
      child: Card(
        child: ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('Huddle'),
          subtitle: Text(
            'Share messages and photos directly with devices on your local '
            'network — no account, no internet required.',
          ),
        ),
      ),
    );

    final header = _DeviceHeader(controller: controller);

    Widget body;
    if (context.isExpandedWidth) {
      // Two-column layout on desktop/tablet.
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header,
            const SizedBox(height: 24),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(children: [thisDevice, agreements]),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(children: [downloads, network, support, about]),
                ),
              ],
            ),
          ],
        ),
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.all(16),
        children: [
          header,
          const SizedBox(height: 24),
          thisDevice,
          agreements,
          downloads,
          network,
          support,
          about,
          const SizedBox(height: 8),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: context.isExpandedWidth ? 920 : 640),
          child: body,
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

  /// Desktop platforms get a native folder picker (the only way a sandboxed
  /// macOS build can be granted write access to a folder outside its own
  /// container); elsewhere we fall back to entering a path by hand.
  Future<void> _editDownloadDir(
          BuildContext context, HuddleController controller) =>
      isDesktopPlatform
          ? _chooseDownloadDir(context, controller)
          : _editDownloadDirManually(context, controller);

  /// Native-picker flow: a small dialog explains the setting and offers to
  /// open the OS folder chooser or restore the default.
  Future<void> _chooseDownloadDir(
      BuildContext context, HuddleController controller) async {
    const choose = 'choose';
    const reset = 'reset';
    final messenger = ScaffoldMessenger.of(context);

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download folder'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Where received files and photos are saved.'),
            const SizedBox(height: 12),
            Text(
              controller.downloadLocation ?? '',
              style: TextStyle(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          if (controller.isCustomDownloadDir)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(reset),
              child: const Text('Use default'),
            ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(choose),
            child: const Text('Choose folder…'),
          ),
        ],
      ),
    );

    if (action == null) return;
    if (action == reset) {
      await controller.setDownloadDirectory(null);
      messenger.showSnackBar(
          const SnackBar(content: Text('Using the default download folder.')));
      return;
    }

    final picked = await getDirectoryPath(
      initialDirectory:
          controller.isCustomDownloadDir ? controller.downloadLocation : null,
      confirmButtonText: 'Use folder',
    );
    if (picked == null) return; // user cancelled the OS picker
    final ok = await controller.setDownloadDirectory(picked);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Files will be saved to $picked'
          : "Couldn't use that folder — check permissions."),
    ));
  }

  /// Manual path entry, used on mobile where the default container folder is
  /// the norm and there is no native directory picker.
  Future<void> _editDownloadDirManually(
      BuildContext context, HuddleController controller) async {
    final field = TextEditingController(
        text: controller.isCustomDownloadDir
            ? (controller.downloadLocation ?? '')
            : '');
    const reset = ' '; // sentinel: "restore default" vs. "cancelled"
    final messenger = ScaffoldMessenger.of(context);

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            title: const Text('Download folder'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Where received files and photos are saved. Enter the full '
                  'path to a folder (most useful on desktop, e.g. your '
                  'Downloads folder). Leave the default unless you have a '
                  'reason to change it.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: field,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Folder path',
                    hintText: '/Users/you/Downloads',
                    errorText: error,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(reset),
                child: const Text('Use default'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final v = field.text.trim();
                  if (v.isEmpty) {
                    setState(() => error = 'Enter a folder path');
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

    if (result == null) return;
    if (result == reset) {
      await controller.setDownloadDirectory(null);
      messenger.showSnackBar(
          const SnackBar(content: Text('Using the default download folder.')));
      return;
    }
    final ok = await controller.setDownloadDirectory(result);
    messenger.showSnackBar(SnackBar(
      content: Text(ok
          ? 'Files will be saved to $result'
          : "Couldn't use that folder — check the path and permissions."),
    ));
  }
}

/// A labelled section: an uppercase label above a card, with bottom spacing so
/// it stacks cleanly in either a single column or a two-column layout.
class _Section extends StatelessWidget {
  const _Section({required this.label, required this.child});
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          child,
        ],
      ),
    );
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
        onPressed: () => confirmEndHuddle(context, controller, peer),
      ),
    );
  }
}
