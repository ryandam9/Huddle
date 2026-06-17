import 'package:flutter/material.dart';

/// Plain-language help and troubleshooting, written for non-technical users.
/// No jargon without an explanation — the goal is that anyone can self-serve
/// the common "my other device isn't showing up" problem.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Help & Troubleshooting')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const _Intro(),
              const SizedBox(height: 20),
              for (final topic in _topics) ...[
                _TopicCard(topic: topic),
                const SizedBox(height: 12),
              ],
              const SizedBox(height: 4),
              _TipBox(),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.support, color: Colors.white, size: 32),
          const SizedBox(height: 12),
          const Text(
            'Trouble connecting?',
            style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Huddle connects devices on the same Wi‑Fi — no internet needed. '
            'If a device isn’t showing up, it’s almost always something about '
            'the network. The steps below fix it in most cases.',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.92), height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _TopicCard extends StatelessWidget {
  const _TopicCard({required this.topic});
  final _Topic topic;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Theme(
        // Remove the default ExpansionTile dividers for a cleaner card.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: topic.expanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          leading: CircleAvatar(
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Icon(topic.icon),
          ),
          title: Text(topic.title,
              style: const TextStyle(fontWeight: FontWeight.w600)),
          children: [
            for (final point in topic.points) _Point(point: point),
          ],
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.point});
  final _HelpPoint point;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(point.icon ?? Icons.check_circle_outline,
              size: 20, color: scheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(point.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, height: 1.3)),
                if (point.detail != null) ...[
                  const SizedBox(height: 2),
                  Text(point.detail!,
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, height: 1.35)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TipBox extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.tips_and_updates_outlined,
              color: scheme.onSecondaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Most common fix: make sure both devices are on the exact same '
              'Wi‑Fi (not a “Guest” network), and on computers allow Huddle '
              'through the firewall when asked.',
              style: TextStyle(
                  color: scheme.onSecondaryContainer, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Content --------------------------------------------------------------

class _HelpPoint {
  const _HelpPoint(this.title, {this.detail, this.icon});
  final String title;
  final String? detail;
  final IconData? icon;
}

class _Topic {
  const _Topic({
    required this.icon,
    required this.title,
    required this.points,
    this.expanded = false,
  });
  final IconData icon;
  final String title;
  final List<_HelpPoint> points;
  final bool expanded;
}

const _topics = <_Topic>[
  _Topic(
    icon: Icons.wifi_find_outlined,
    title: "The other device isn't showing up",
    expanded: true,
    points: [
      _HelpPoint(
        'Put both devices on the same Wi‑Fi',
        detail: 'Check the Wi‑Fi name on each device — they must match '
            'exactly. A phone using mobile data instead of Wi‑Fi won’t work.',
        icon: Icons.wifi,
      ),
      _HelpPoint(
        'Avoid “Guest” Wi‑Fi networks',
        detail: 'Guest networks usually stop devices from seeing each other. '
            'Connect both devices to your normal home or office Wi‑Fi.',
        icon: Icons.no_accounts_outlined,
      ),
      _HelpPoint(
        'Allow Huddle to find devices (iPhone, iPad, Mac)',
        detail: 'The first time you open Huddle it asks permission to find '
            'devices on your network — tap Allow. If you tapped “Don’t Allow”, '
            'turn it back on in Settings › Privacy & Security › Local Network '
            '› Huddle.',
        icon: Icons.shield_outlined,
      ),
      _HelpPoint(
        'Let Huddle through the firewall (computers)',
        detail: 'A firewall is built‑in security that can block apps from '
            'talking on the network. On Windows, click “Allow access” on the '
            'popup the first time (tick Private networks). On Mac, open System '
            'Settings › Network › Firewall and allow Huddle, or turn the '
            'firewall off briefly to test.',
        icon: Icons.security_outlined,
      ),
      _HelpPoint(
        'Turn off any VPN on the computer',
        detail: 'A VPN reroutes your connection and can hide the other devices '
            'on your Wi‑Fi. Disconnect it and try again.',
        icon: Icons.vpn_key_off_outlined,
      ),
      _HelpPoint(
        'Give it a few seconds',
        detail: 'Devices announce themselves every few seconds. Wait about 10 '
            'seconds after opening Huddle on both devices.',
        icon: Icons.timer_outlined,
      ),
      _HelpPoint(
        'Still nothing? Reset the connection',
        detail: 'Turn Wi‑Fi off and on again on both devices and reopen '
            'Huddle. As a last resort, restart your router — some routers keep '
            'devices apart for “security”.',
        icon: Icons.restart_alt,
      ),
    ],
  ),
  _Topic(
    icon: Icons.link,
    title: 'How do I connect two devices?',
    points: [
      _HelpPoint('Open Huddle on both devices on the same Wi‑Fi.',
          icon: Icons.looks_one_outlined),
      _HelpPoint('On the Devices tab, find the other device and tap “Pair”.',
          icon: Icons.looks_two_outlined),
      _HelpPoint('A 6‑digit code appears on your screen.',
          icon: Icons.looks_3_outlined),
      _HelpPoint(
        'On the other device, type that same code when prompted and confirm.',
        icon: Icons.looks_4_outlined,
      ),
      _HelpPoint(
        'That’s it — you’re paired',
        detail: 'You can now exchange messages and photos. You only pair once '
            'per device; the agreement is remembered.',
        icon: Icons.celebration_outlined,
      ),
    ],
  ),
  _Topic(
    icon: Icons.forum_outlined,
    title: "Messages or photos aren't arriving",
    points: [
      _HelpPoint(
        'Check the other device is online',
        detail: 'A green dot means online. A grey dot means Huddle is closed '
            'on that device, or it has left the Wi‑Fi.',
        icon: Icons.circle_outlined,
      ),
      _HelpPoint(
        'Messages sent while offline wait on your side',
        detail: 'They show in your chat, but the other device needs to be '
            'online to receive new ones.',
        icon: Icons.schedule_send_outlined,
      ),
      _HelpPoint(
        'Keep Huddle open on phones',
        detail: 'When an app is in the background, the phone may pause its '
            'networking. Keep Huddle on screen while sharing.',
        icon: Icons.stay_current_portrait_outlined,
      ),
    ],
  ),
  _Topic(
    icon: Icons.lock_outline,
    title: 'Is my information private?',
    points: [
      _HelpPoint(
        'Yes — nothing leaves your network',
        detail: 'Huddle never uses the internet or any server. Messages and '
            'photos travel straight from one device to the other over your '
            'local Wi‑Fi, and are stored only on your devices.',
        icon: Icons.verified_user_outlined,
      ),
    ],
  ),
  _Topic(
    icon: Icons.help_outline,
    title: 'How does Huddle work?',
    points: [
      _HelpPoint(
        'Devices announce themselves',
        detail: 'Each device quietly says “I’m here” on your Wi‑Fi so other '
            'devices running Huddle can list it.',
        icon: Icons.podcasts,
      ),
      _HelpPoint(
        'You pair to agree to talk',
        detail: 'The 6‑digit code makes sure both people mean to connect.',
        icon: Icons.handshake_outlined,
      ),
      _HelpPoint(
        'Then they talk directly',
        detail: 'Paired devices send messages and photos straight to each '
            'other — no middle‑man, no cloud.',
        icon: Icons.swap_horiz,
      ),
    ],
  ),
];
