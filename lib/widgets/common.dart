import 'package:flutter/material.dart';

import '../ui_helpers.dart';

/// A circular avatar tinted from a stable id, with a platform glyph.
class HuddleAvatar extends StatelessWidget {
  const HuddleAvatar({
    super.key,
    required this.id,
    required this.name,
    required this.platform,
    this.radius = 24,
    this.showStatus = false,
    this.online = false,
  });

  final String id;
  final String name;
  final String platform;
  final double radius;
  final bool showStatus;
  final bool online;

  @override
  Widget build(BuildContext context) {
    final color = colorForId(id);
    final avatar = Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, Color.lerp(color, Colors.black, 0.18)!],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(platformIcon(platform), color: Colors.white, size: radius),
    );

    if (!showStatus) return avatar;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          bottom: -1,
          child: StatusDot(online: online, ringColor: _bg(context)),
        ),
      ],
    );
  }

  Color _bg(BuildContext context) => Theme.of(context).colorScheme.surface;
}

/// A small online/offline indicator dot with a ring so it reads on any bg.
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.online,
    required this.ringColor,
    this.size = 13,
  });

  final bool online;
  final Color ringColor;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: online ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2.5),
      ),
    );
  }
}

/// A centered, friendly placeholder for empty screens.
class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Optional call-to-action shown below the message (e.g. a Help button).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 44, color: scheme.primary),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              ),
              if (action != null) ...[
                const SizedBox(height: 20),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
