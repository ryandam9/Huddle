import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device.dart';
import '../responsive.dart';
import '../state/huddle_controller.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// Lists devices discovered on the local network and lets the user start a
/// code-verified pairing with any of them. Responsive: a list on phones, a
/// card grid on wide screens.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();
    final devices = controller.devices;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Devices'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _ScanningChip(count: devices.length),
          ),
        ],
      ),
      body: Column(
        children: [
          _NetworkBanner(name: controller.identity.name, ip: controller.wifiIp),
          Expanded(
            child: devices.isEmpty
                ? const EmptyStateView(
                    icon: Icons.radar,
                    title: 'Looking for devices…',
                    message: 'Open Huddle on another device on the same Wi-Fi '
                        'network and it will appear here automatically.',
                  )
                : _DeviceCollection(devices: devices),
          ),
        ],
      ),
    );
  }
}

class _ScanningChip extends StatelessWidget {
  const _ScanningChip({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.sensors, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text('$count nearby',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scheme.primary, scheme.tertiary],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.podcasts, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('You appear as “$name”',
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(
                    ip == null
                        ? 'Broadcasting on your local network'
                        : 'On the network at $ip',
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCollection extends StatelessWidget {
  const _DeviceCollection({required this.devices});
  final List<Device> devices;

  @override
  Widget build(BuildContext context) {
    if (context.isCompact) {
      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: devices.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) => _DeviceCard(device: devices[i]),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 420,
        mainAxisExtent: 92,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: devices.length,
      itemBuilder: (_, i) => _DeviceCard(device: devices[i]),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.device});
  final Device device;

  @override
  Widget build(BuildContext context) {
    final controller = context.read<HuddleController>();
    final paired = controller.isPaired(device.id);
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: InkWell(
        onTap: () => paired
            ? _openChat(context, controller)
            : _pair(context, controller),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              HuddleAvatar(
                id: device.id,
                name: device.name,
                platform: device.platform,
                showStatus: true,
                online: device.isOnline,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(device.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 15)),
                        ),
                        if (paired) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.verified,
                              size: 15, color: scheme.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text('${device.platform} · ${device.host}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              paired
                  ? FilledButton.tonalIcon(
                      onPressed: () => _openChat(context, controller),
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: const Text('Open'),
                    )
                  : FilledButton.icon(
                      onPressed: () => _pair(context, controller),
                      icon: const Icon(Icons.link, size: 18),
                      label: const Text('Pair'),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  void _pair(BuildContext context, HuddleController controller) {
    controller.startPairing(device);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PairingCodeDialog(),
    );
  }

  void _openChat(BuildContext context, HuddleController controller) {
    final peer = controller.peers.firstWhere((p) => p.id == device.id);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(peer: peer)),
    );
  }
}

/// Shown to the initiator after tapping Pair: displays the one-time code and
/// reflects the handshake's progress.
class PairingCodeDialog extends StatelessWidget {
  const PairingCodeDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<HuddleController>(
      builder: (context, controller, _) {
        final pairing = controller.outgoingPairing;
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
                  Text('Enter this code on ${pairing.peerName} to confirm:',
                      textAlign: TextAlign.center),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      _spaced(pairing.code),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 8,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: 12),
                      Flexible(
                          child: Text('Waiting for ${pairing.peerName}…')),
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
              color: const Color(0xFF22C55E),
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
          Icon(icon, color: color, size: 52),
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
