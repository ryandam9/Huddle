import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/peer.dart';
import '../state/huddle_controller.dart';
import '../ui_helpers.dart';
import 'chat_screen.dart';
import 'home_screen.dart';

/// Lists every peer the user has an agreement with, newest activity first,
/// and opens the conversation on tap.
class HuddlesScreen extends StatelessWidget {
  const HuddlesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();
    final peers = controller.peers;

    return Scaffold(
      appBar: AppBar(title: const Text('Huddles')),
      body: peers.isEmpty
          ? const _EmptyHuddles()
          : ListView.separated(
              itemCount: peers.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) =>
                  _PeerTile(peer: peers[i], controller: controller),
            ),
    );
  }
}

class _PeerTile extends StatelessWidget {
  const _PeerTile({required this.peer, required this.controller});
  final Peer peer;
  final HuddleController controller;

  @override
  Widget build(BuildContext context) {
    final messages = controller.conversation(peer.id);
    final last = messages.isEmpty ? null : messages.last;
    final unread = controller.unreadFor(peer.id);
    final online = controller.isOnline(peer.id);

    return ListTile(
      leading: HuddleAvatar(
        id: peer.id,
        name: peer.name,
        platform: peer.platform,
      ),
      title: Text(peer.name),
      subtitle: Text(
        _preview(last),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            online ? 'online' : 'offline',
            style: TextStyle(
              fontSize: 11,
              color: online ? Colors.green : Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          if (unread > 0)
            Badge(label: Text('$unread'))
          else if (last != null)
            Text(formatTime(last.sentAt),
                style: const TextStyle(fontSize: 11)),
        ],
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(peer: peer)),
      ),
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

class _EmptyHuddles extends StatelessWidget {
  const _EmptyHuddles();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined,
                size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text('No huddles yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Head to the Devices tab and pair with someone to start '
              'sharing messages and photos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
