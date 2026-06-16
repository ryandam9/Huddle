import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/peer.dart';
import '../state/huddle_controller.dart';
import '../ui_helpers.dart';
import 'home_screen.dart';

/// A one-to-one conversation with a paired [Peer]: text messages and photos.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.peer});
  final Peer peer;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

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

  Future<void> _sendPhoto(HuddleController controller) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = result?.files.single.path;
    if (path == null) return;

    setState(() => _sending = true);
    final ok = await controller.sendPhoto(widget.peer.id, path);
    if (mounted) {
      setState(() => _sending = false);
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo saved, but peer is offline.')),
        );
      }
    }
  }

  Future<void> _confirmUnpair(HuddleController controller) async {
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('End huddle?'),
        content: Text(
          'This removes your agreement with ${widget.peer.name} and deletes '
          'this conversation. You can pair again later.',
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
      await controller.unpair(widget.peer.id);
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();
    final messages = controller.conversation(widget.peer.id);
    final online = controller.isOnline(widget.peer.id);

    // Clear the unread badge for this conversation once shown.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      controller.markRead(widget.peer.id);
    });
    _scrollToBottom();

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            HuddleAvatar(
              id: widget.peer.id,
              name: widget.peer.name,
              platform: widget.peer.platform,
              radius: 16,
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.peer.name, style: const TextStyle(fontSize: 16)),
                Text(
                  online ? 'online' : 'offline',
                  style: TextStyle(
                    fontSize: 12,
                    color: online ? Colors.greenAccent : Colors.white70,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'unpair') _confirmUnpair(controller);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'unpair', child: Text('End huddle')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.isEmpty
                ? const Center(child: Text('No messages yet. Say hi!'))
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _Bubble(message: messages[i]),
                  ),
          ),
          _Composer(
            controller: _input,
            sending: _sending,
            onSend: () => _sendText(controller),
            onAttach: () => _sendPhoto(controller),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (message.kind == MessageKind.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        child: Center(
          child: Text(
            message.text ?? '',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.outline),
          ),
        ),
      );
    }

    final mine = message.mine;
    final bg = mine ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = mine ? scheme.onPrimary : scheme.onSurface;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72),
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.kind == MessageKind.photo)
              _PhotoContent(message: message, tint: fg)
            else
              Text(message.text ?? '', style: TextStyle(color: fg)),
            const SizedBox(height: 2),
            Text(
              formatTime(message.sentAt),
              style: TextStyle(fontSize: 10, color: fg.withValues(alpha: 0.7)),
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
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.broken_image, color: tint, size: 18),
          const SizedBox(width: 6),
          Text(message.fileName ?? 'Photo', style: TextStyle(color: tint)),
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 240),
        child: Image.file(File(path), fit: BoxFit.cover),
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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Row(
          children: [
            IconButton(
              onPressed: sending ? null : onAttach,
              icon: sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.photo_outlined),
              tooltip: 'Send a photo',
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Message…',
                  filled: true,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton.filled(
              onPressed: onSend,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
