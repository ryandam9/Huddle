import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/peer.dart';
import '../state/huddle_controller.dart';
import '../ui_helpers.dart';
import '../widgets/common.dart';

/// Full-screen conversation used for phone navigation (own AppBar + back).
class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key, required this.peer});
  final Peer peer;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();
    final online = controller.isOnline(peer.id);

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
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
            Expanded(child: _TitleText(peer: peer, online: online)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'End huddle',
            icon: const Icon(Icons.link_off),
            onPressed: () async {
              final navigator = Navigator.of(context);
              if (await confirmEndHuddle(context, controller, peer)) {
                navigator.pop();
              }
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ChatView(peer: peer),
    );
  }
}

class _TitleText extends StatelessWidget {
  const _TitleText({required this.peer, required this.online});
  final Peer peer;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(peer.name,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
        Text(
          online ? 'Online' : 'Offline',
          style: TextStyle(
            fontSize: 12,
            color: online ? const Color(0xFF22C55E) : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// The reusable conversation body (message list + composer), with no AppBar so
/// it can be embedded in a desktop master-detail pane.
class ChatView extends StatefulWidget {
  const ChatView({super.key, required this.peer});
  final Peer peer;

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _sendText(HuddleController controller) async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    final ok = await controller.sendText(widget.peer.id, text);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message saved, but peer is offline.')),
      );
    }
  }

  Future<void> _sendPhotos(HuddleController controller) async {
    // Multi-select works across every platform (unlike a directory picker);
    // one or many, they're handed to the controller's background batch sender.
    final picked = await ImagePicker().pickMultiImage();
    if (picked.isEmpty) return;
    final paths = [for (final x in picked) x.path];
    // Fire-and-forget: the batch streams out in the background and its progress
    // is surfaced from controller.transfer.
    unawaited(controller.sendPhotos(widget.peer.id, paths));
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();
    final messages = controller.conversation(widget.peer.id);

    final transfer = controller.transfer;
    final sendingHere = transfer != null &&
        transfer.peerId == widget.peer.id &&
        !transfer.isComplete;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.markRead(widget.peer.id);
    });
    _scrollToBottom();

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? const EmptyStateView(
                  icon: Icons.waving_hand_outlined,
                  title: 'Say hello',
                  message: 'Send the first message or a photo to get started.',
                )
              : Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
                      itemCount: messages.length,
                      itemBuilder: (_, i) => _Bubble(message: messages[i]),
                    ),
                  ),
                ),
        ),
        if (sendingHere) _TransferStrip(progress: transfer),
        _Composer(
          controller: _input,
          sending: sendingHere,
          onSend: () => _sendText(controller),
          onAttach: () => _sendPhotos(controller),
        ),
      ],
    );
  }
}

/// Shared confirm dialog + unpair, returns true if the huddle was ended.
Future<bool> confirmEndHuddle(
    BuildContext context, HuddleController controller, Peer peer) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('End huddle?'),
      content: Text(
        'This removes your agreement with ${peer.name} and deletes this '
        'conversation. You can pair again later.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('End huddle')),
      ],
    ),
  );
  if (ok == true) {
    await controller.unpair(peer.id);
    return true;
  }
  return false;
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (message.kind == MessageKind.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.text ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    final mine = message.mine;
    final bg = mine ? scheme.primary : scheme.surfaceContainerHigh;
    final fg = mine ? scheme.onPrimary : scheme.onSurface;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 460),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        padding: message.kind == MessageKind.photo
            ? const EdgeInsets.all(4)
            : const EdgeInsets.fromLTRB(14, 10, 14, 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 4),
            bottomRight: Radius.circular(mine ? 4 : 18),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.kind == MessageKind.photo)
              _PhotoContent(message: message, tint: fg)
            else
              Text(message.text ?? '',
                  style: TextStyle(color: fg, height: 1.3, fontSize: 15)),
            Padding(
              padding: EdgeInsets.only(
                  top: 3, right: message.kind == MessageKind.photo ? 6 : 0),
              child: Text(
                formatTime(message.sentAt),
                style: TextStyle(
                    fontSize: 10, color: fg.withValues(alpha: 0.7)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoContent extends StatelessWidget {
  const _PhotoContent({required this.message, required this.tint});
  final ChatMessage message;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final path = message.filePath;
    if (path == null || !File(path).existsSync()) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: tint, size: 18),
            const SizedBox(width: 6),
            Text(message.fileName ?? 'Photo', style: TextStyle(color: tint)),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260, maxWidth: 320),
        child: Image.file(File(path), fit: BoxFit.cover),
      ),
    );
  }
}

/// A slim progress bar shown above the composer while a batch of photos is
/// streaming out in the background.
class _TransferStrip extends StatelessWidget {
  const _TransferStrip({required this.progress});
  final TransferProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = progress.completed;
    final total = progress.total;
    return Material(
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                progress.failed > 0
                    ? 'Sending photos… $done/$total (${progress.failed} failed)'
                    : 'Sending photos… $done/$total',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onAttach,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 820),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                onPressed: sending ? null : onAttach,
                style: IconButton.styleFrom(
                  backgroundColor: scheme.surfaceContainerHigh,
                  padding: const EdgeInsets.all(12),
                ),
                icon: sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.add_photo_alternate_outlined),
                tooltip: 'Send a photo',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  decoration: const InputDecoration(
                    hintText: 'Message…',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: onSend,
                style: IconButton.styleFrom(padding: const EdgeInsets.all(12)),
                icon: const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
