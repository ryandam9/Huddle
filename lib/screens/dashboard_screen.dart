import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../state/huddle_controller.dart';
import 'chat_screen.dart';
import 'home_screen.dart';

/// Lists every device currently visible on the local network and lets the
/// user start a pairing agreement with any of them.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();
    final devices = controller.devices;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices on your network'),
      ),
      body: Column(
        children: [
          _NetworkBanner(
            name: controller.identity.name,
            ip: controller.wifiIp,
          ),
          Expanded(
            child: devices.isEmpty
                ? const _EmptyState()
                : ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, indent: 72),
                    itemBuilder: (_, i) => _DeviceTile(device: devices[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _NetworkBanner extends StatelessWidget {
  const _NetworkBanner({required this.name, required this.ip});
  final String name;
  final String? ip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.primaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Icon(Icons.podcasts, color: scheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('You appear as "$name"',
                    style: TextStyle(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600)),
                Text(
                  ip == null ? 'Broadcasting on the local network' : 'IP $ip',
                  style: TextStyle(
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                      fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});
  final Device device;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HuddleController>();
    final paired = controller.isPaired(device.id);
    final online = device.isOnline;

    return ListTile(
      leading: Stack(
        children: [
          HuddleAvatar(
            id: device.id,
            name: device.name,
            platform: device.platform,
          ),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: online ? Colors.green : Colors.grey,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2),
              ),
            ),
          ),
        ],
      ),
      title: Text(device.name),
      subtitle: Text(
        '${device.platform} · ${device.host}'
        '${paired ? ' · paired' : ''}',
      ),
      trailing: paired
          ? FilledButton.tonalIcon(
              onPressed: () => _openChat(context, controller, device.id),
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: const Text('Open'),
            )
          : FilledButton.icon(
              onPressed: () => _pair(context, controller, device),
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Pair'),
            ),
    );
  }

  void _pair(BuildContext context, HuddleController controller, Device device) {
    controller.startPairing(device);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PairingCodeDialog(),
    );
  }

  void _openChat(
      BuildContext context, HuddleController controller, String peerId) {
    final peer = controller.peers.firstWhere((p) => p.id == peerId);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(peer: peer)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.radar,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text(
              'Looking for devices…',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              'Open Huddle on another device connected to the same Wi-Fi '
              'network. It will appear here automatically.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown to the *initiator* after tapping Pair: displays the one-time code to
/// read out to the other person and reflects the handshake's progress.
class PairingCodeDialog extends StatelessWidget {
  const PairingCodeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HuddleController>(
      builder: (context, controller, _) {
        final pairing = controller.outgoingPairing;
        // Cleared out from under us — nothing left to show.
        if (pairing == null) return const SizedBox.shrink();

        final scheme = Theme.of(context).colorScheme;

        void close() {
          controller.cancelPairing();
          Navigator.of(context).pop();
        }

        switch (pairing.status) {
          case PairStatus.waiting:
            return AlertDialog(
              title: Text('Pair with ${pairing.peerName}'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Enter this code on ${pairing.peerName} to confirm:',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _spaced(pairing.code),
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 8,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Text('Waiting for ${pairing.peerName}…'),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: close, child: const Text('Cancel')),
              ],
            );

          case PairStatus.success:
            return _ResultDialog(
              icon: Icons.check_circle,
              color: Colors.green,
              message: 'Paired with ${pairing.peerName}.',
              onClose: close,
            );
          case PairStatus.declined:
            return _ResultDialog(
              icon: Icons.cancel,
              color: scheme.error,
              message: '${pairing.peerName} declined the request.',
              onClose: close,
            );
          case PairStatus.mismatch:
            return _ResultDialog(
              icon: Icons.error,
              color: scheme.error,
              message: "The code didn't match. Try pairing again.",
              onClose: close,
            );
          case PairStatus.unreachable:
            return _ResultDialog(
              icon: Icons.wifi_off,
              color: scheme.error,
              message: 'Could not reach ${pairing.peerName}.',
              onClose: close,
            );
        }
      },
    );
  }

  /// "048213" -> "048 213" for readability.
  String _spaced(String code) {
    final mid = code.length ~/ 2;
    return '${code.substring(0, mid)} ${code.substring(mid)}';
  }
}

class _ResultDialog extends StatelessWidget {
  const _ResultDialog({
    required this.icon,
    required this.color,
    required this.message,
    required this.onClose,
  });

  final IconData icon;
  final Color color;
  final String message;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 48),
          const SizedBox(height: 16),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        FilledButton(onPressed: onClose, child: const Text('Done')),
      ],
    );
  }
}
