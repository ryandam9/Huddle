import 'package:flutter/material.dart';

/// A radar-style pulse: concentric rings expand and fade outward from a center
/// glyph, evoking "searching the network". Used while looking for devices.
class RadarPulse extends StatefulWidget {
  const RadarPulse({
    super.key,
    this.size = 110,
    this.icon = Icons.wifi_tethering,
  });

  final double size;
  final IconData icon;

  @override
  State<RadarPulse> createState() => _RadarPulseState();
}

class _RadarPulseState extends State<RadarPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 3; i++) _ring(i, scheme.primary),
              Container(
                width: widget.size * 0.36,
                height: widget.size * 0.36,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon,
                    color: scheme.onPrimaryContainer,
                    size: widget.size * 0.2),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _ring(int index, Color color) {
    // Stagger the three rings across the cycle.
    final t = (_controller.value + index / 3) % 1.0;
    final scale = 0.36 + t * 0.64;
    final opacity = ((1.0 - t) * 0.55).clamp(0.0, 1.0);
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
        ),
      ),
    );
  }
}
