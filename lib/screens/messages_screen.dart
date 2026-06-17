import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/peer.dart';
import '../responsive.dart';
import '../state/huddle_controller.dart';
import '../ui_helpers.dart';
import '../widgets/common.dart';
import 'chat_screen.dart';

/// Responsive conversations view. On phones it's a list that pushes a full
/// [ChatScreen]; on wide screens it's a master-detail layout with the peer list
/// on the left and the live conversation on the right.
class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  String? _selectedId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();
    final peers = controller.peers;

    if (context.isCompact) {
      return Scaffold(
        appBar: AppBar(title: const Text('Huddles')),
        body: peers.isEmpty
            ? const _NoHuddles()
            : PeerList(
                peers: peers,
                onSelect: (peer) => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ChatScreen(peer: peer)),
                ),
              ),
      );
    }

    // Keep selection valid as peers come and go.
    final selected =
        peers.where((p) => p.id == _selectedId).cast<Peer?>().firstOrNull;

    return Row(
      children: [
        SizedBox(
          width: 340,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Huddles'),
              automaticallyImplyLeading: false,
            ),
            body: peers.isEmpty
                ? const _NoHuddles()
                : PeerList(
                    peers: peers,
                    selectedId: _selectedId,
                    onSelect: (peer) => setState(() => _selectedId = peer.id),
                  ),
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const _NoSelection()
              : _DetailPane(
                  peer: selected,
                  onUnpaired: () => setState(() => _selectedId = null),
                ),
        ),
      ],
    );
  }
}

/// The right-hand conversation pane on wide layouts (header + [ChatView]).
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.peer, required this.onUnpaired});
  final Peer peer;
  final VoidCallback onUnpaired;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();
    final online = controller.isOnline(peer.id);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(
          children: [
            HuddleAvatar(
              id: peer.id,
              name: peer.name,
              platform: peer.platform,
              radius: 18,
              showStatus: true,
              online: online,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(peer.name,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                Text(
                  online ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: online
                        ? const Color(0xFF22C55E)
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'End huddle',
            icon: const Icon(Icons.link_off),
            onPressed: () async {
              if (await confirmEndHuddle(context, controller, peer)) {
                onUnpaired();
              }
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ChatView(key: ValueKey(peer.id), peer: peer),
    );
  }
}

/// Selectable list of paired peers with last-message preview and unread badge.
class PeerList extends StatelessWidget {
  const PeerList({
    super.key,
    required this.peers,
    required this.onSelect,
    this.selectedId,
  });

  final List<Peer> peers;
  final ValueChanged<Peer> onSelect;
  final String? selectedId;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      itemCount: peers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 2),
      itemBuilder: (_, i) {
        final peer = peers[i];
        final messages = controller.conversation(peer.id);
        final last = messages.isEmpty ? null : messages.last;
        final unread = controller.unreadFor(peer.id);
        final online = controller.isOnline(peer.id);

        return ListTile(
          selected: peer.id == selectedId,
          selectedTileColor:
              Theme.of(context).colorScheme.primaryContainer.withValues(
                    alpha: 0.5,
                  ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: HuddleAvatar(
            id: peer.id,
            name: peer.name,
            platform: peer.platform,
            showStatus: true,
            online: online,
          ),
          title: Text(peer.name,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_preview(last),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (last != null)
                Text(formatTime(last.sentAt),
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              if (unread > 0) Badge(label: Text('$unread')),
            ],
          ),
          onTap: () => onSelect(peer),
        );
      },
    );
  }

  String _preview(ChatMessage? m) {
    if (m == null) return 'Say hello 👋';
    return switch (m.kind) {
      MessageKind.photo => '📷 Photo',
      MessageKind.system => m.text ?? '',
      MessageKind.text => '${m.mine ? 'You: ' : ''}${m.text ?? ''}',
    };
  }
}

class _NoHuddles extends StatelessWidget {
  const _NoHuddles();
  @override
  Widget build(BuildContext context) {
    return const EmptyStateView(
      icon: Icons.forum_outlined,
      title: 'No huddles yet',
      message: 'Pair with a device from the Devices tab to start sharing '
          'messages and photos.',
    );
  }
}

class _NoSelection extends StatelessWidget {
  const _NoSelection();
  @override
  Widget build(BuildContext context) {
    return const EmptyStateView(
      icon: Icons.chat_bubble_outline,
      title: 'Your conversations',
      message: 'Select a huddle on the left to open the conversation.',
    );
  }
}
