import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart' show getDirectoryPath;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
import '../models/peer.dart';
import '../responsive.dart';
import '../services/media_scan.dart';
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
          PopupMenuButton<String>(
            tooltip: 'Conversation options',
            onSelected: (value) async {
              final navigator = Navigator.of(context);
              if (value == 'clear') {
                await confirmClearConversation(context, controller, peer);
              } else if (value == 'end' &&
                  await confirmEndHuddle(context, controller, peer)) {
                navigator.pop();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_sweep_outlined),
                  title: Text('Clear messages'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'end',
                child: ListTile(
                  leading: Icon(Icons.link_off),
                  title: Text('End huddle'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
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

  /// Message count at the previous build. Side effects (mark-read, auto-scroll)
  /// fire only when this changes — i.e. when messages actually arrive — rather
  /// than on every rebuild (which also happens for device pruning, transfer
  /// progress, theme/keyboard changes, etc.) as it used to (finding #19).
  int _lastCount = 0;

  @override
  void didUpdateWidget(covariant ChatView old) {
    super.didUpdateWidget(old);
    // A desktop master-detail switch reuses this State for a different peer:
    // treat it as a fresh conversation and jump to its latest message.
    if (old.peer.id != widget.peer.id) {
      _lastCount = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToBottom();
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool get _atBottom {
    if (!_scroll.hasClients) return true; // before first layout → start pinned
    final p = _scroll.position;
    return p.maxScrollExtent - p.pixels < 120;
  }

  void _jumpToBottom() {
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  /// Reacts to new messages while the conversation is on screen: mark them read
  /// and keep the view pinned to the bottom, but only if the user was already
  /// near it — so scrolling up to read history isn't yanked back down.
  void _onMessagesAppeared(HuddleController controller) {
    final wasAtBottom = _atBottom;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      controller.markRead(widget.peer.id);
      if (wasAtBottom) _jumpToBottom();
    });
  }

  Future<void> _sendText(HuddleController controller) async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    // Delivery happens in the background with retry; the bubble's status tick
    // (sending → delivered/failed) reflects the outcome.
    await controller.sendText(widget.peer.id, text);
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

  /// Desktop-only: pick a folder and send every image in it as one batch.
  Future<void> _sendFolder(HuddleController controller) async {
    final messenger = ScaffoldMessenger.of(context);
    final dir = await getDirectoryPath();
    if (dir == null) return; // cancelled
    final paths = await listImageFiles(dir);
    if (paths.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No photos found in that folder.')),
      );
      return;
    }
    unawaited(controller.sendPhotos(widget.peer.id, paths));
  }

  /// Long-press on a bubble: confirm and delete the message locally.
  Future<void> _confirmDeleteMessage(
      HuddleController controller, ChatMessage message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This removes it from this device only.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await controller.deleteMessage(widget.peer.id, message.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<HuddleController>();
    final messages = controller.conversation(widget.peer.id);

    final transfer = controller.transfer;
    final sendingHere = transfer != null &&
        transfer.peerId == widget.peer.id &&
        !transfer.isComplete;

    if (messages.length != _lastCount) {
      _lastCount = messages.length;
      _onMessagesAppeared(controller);
    }

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
                      itemBuilder: (_, i) {
                        final m = messages[i];
                        return GestureDetector(
                          onLongPress: () => _confirmDeleteMessage(controller, m),
                          child: _Bubble(
                            message: m,
                            onRetry:
                                (m.mine && m.status == MessageStatus.failed)
                                    ? () => controller.retryMessage(
                                        widget.peer.id, m.id)
                                    : null,
                          ),
                        );
                      },
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
          onAttachFolder:
              isDesktopPlatform ? () => _sendFolder(controller) : null,
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

/// Confirm dialog + clear the conversation history (the agreement is kept).
Future<void> confirmClearConversation(
    BuildContext context, HuddleController controller, Peer peer) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Clear messages?'),
      content: Text(
        'This deletes the conversation with ${peer.name} on this device. '
        'Your agreement stays, so you can keep chatting.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear')),
      ],
    ),
  );
  if (ok == true) {
    await controller.clearConversation(peer.id);
    messenger.showSnackBar(
        const SnackBar(content: Text('Conversation cleared.')));
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, this.onRetry});
  final ChatMessage message;

  /// Invoked when the user taps a failed message's indicator to resend it.
  final VoidCallback? onRetry;

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
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatTime(message.sentAt),
                    style: TextStyle(
                        fontSize: 10, color: fg.withValues(alpha: 0.7)),
                  ),
                  if (message.mine) ...[
                    const SizedBox(width: 4),
                    // Shown for photos too, not just text, so a failed photo is
                    // visible and retryable rather than silently stuck (#21).
                    _StatusTick(
                        status: message.status, tint: fg, onRetry: onRetry),
                  ],
                ],
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
    if (path == null) return _placeholder();
    // Tap (touch) or click (desktop) opens the photo full-screen; a Hero links
    // the thumbnail to the viewer so the transition animates from the bubble.
    return GestureDetector(
      onTap: () => _openViewer(context, path),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260, maxWidth: 320),
            child: Hero(
              tag: 'photo-${message.id}',
              child: Image.file(
                File(path),
                fit: BoxFit.cover,
                // Decode at roughly twice the bubble's size (for hi-dpi) rather
                // than the photo's full resolution, so a large image doesn't
                // cost megabytes of memory just to render a thumbnail (#20).
                cacheWidth: 640,
                cacheHeight: 520,
                // Handle a missing/unreadable/corrupt file asynchronously here
                // instead of a synchronous File.existsSync() in build, which
                // blocks the UI thread on every rebuild.
                errorBuilder: (_, _, _) => _placeholder(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openViewer(BuildContext context, String path) {
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (_, _, _) => _PhotoViewer(message: message, path: path),
      ),
    );
  }

  Widget _placeholder() => Padding(
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

/// Full-screen photo preview opened by tapping a photo bubble. Renders the
/// image at full resolution inside an [InteractiveViewer] (pinch-to-zoom on
/// touch, scroll-to-zoom on desktop); tapping the backdrop or the close button
/// dismisses it.
class _PhotoViewer extends StatelessWidget {
  const _PhotoViewer({required this.message, required this.path});
  final ChatMessage message;
  final String path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Tap anywhere on the backdrop to dismiss.
          Positioned.fill(
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Center(
                  child: Hero(
                    tag: 'photo-${message.id}',
                    child: Image.file(
                      File(path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.white70,
                        size: 64,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
          if (message.fileName != null)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    message.fileName!,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Delivery indicator on an outgoing text bubble: a clock while sending, a
/// double-check once the peer acknowledges, an alert if it couldn't be sent.
class _StatusTick extends StatelessWidget {
  const _StatusTick({required this.status, required this.tint, this.onRetry});
  final MessageStatus status;
  final Color tint;

  /// When the message failed, tapping the indicator resends it.
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MessageStatus.sending:
        return Icon(Icons.schedule,
            size: 12, color: tint.withValues(alpha: 0.7));
      case MessageStatus.delivered:
        return Icon(Icons.done_all,
            size: 13, color: tint.withValues(alpha: 0.9));
      case MessageStatus.read:
        // A distinct accent for "seen", à la the familiar blue double-check.
        return const Icon(Icons.done_all, size: 13, color: Color(0xFF7FD1FF));
      case MessageStatus.failed:
        final icon = Icon(Icons.error_outline,
            size: 13, color: Theme.of(context).colorScheme.error);
        if (onRetry == null) return icon;
        return GestureDetector(
          onTap: onRetry,
          child: Tooltip(
            message: 'Not delivered — tap to retry',
            child: Padding(padding: const EdgeInsets.all(2), child: icon),
          ),
        );
    }
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
    this.onAttachFolder,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttach;

  /// Send-a-whole-folder action; null hides the button (mobile/web).
  final VoidCallback? onAttachFolder;

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
                tooltip: 'Send photos',
              ),
              if (onAttachFolder != null) ...[
                const SizedBox(width: 4),
                IconButton(
                  onPressed: sending ? null : onAttachFolder,
                  style: IconButton.styleFrom(
                    backgroundColor: scheme.surfaceContainerHigh,
                    padding: const EdgeInsets.all(12),
                  ),
                  icon: const Icon(Icons.folder_outlined),
                  tooltip: 'Send a folder of photos',
                ),
              ],
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
