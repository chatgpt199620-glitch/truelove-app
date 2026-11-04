import 'dart:math' as math;
import 'package:flutter/material.dart';

/// How the heart moves (it always plays ONCE and then stays still).
enum HeartAnimation {
  /// Heart falls in from above, bounces a little, gives one "heartbeat" and stops.
  dropIn,

  /// Heart jumps up once, lands with a small bounce and stops.
  jump,
}

/// An animated ❤ for the TrueLove logo / title.
///
///   const AnimatedHeart(size: 85)                                   // drops in from above
///   const AnimatedHeart(size: 18, color: Colors.white,
///                       animation: HeartAnimation.jump)             // jumps once
///
/// Tap the heart to play the animation again.
/// If the phone has "remove animations" turned on, the heart is simply shown still.
class AnimatedHeart extends StatefulWidget {
  final double size;
  final Color color;
  final HeartAnimation animation;

  /// Wait this long before the animation starts.
  final Duration delay;

  /// Let the user tap the heart to replay the animation.
  final bool replayOnTap;

  const AnimatedHeart({
    super.key,
    this.size = 24,
    this.color = Colors.red,
    this.animation = HeartAnimation.dropIn,
    this.delay = Duration.zero,
    this.replayOnTap = true,
  });

  @override
  State<AnimatedHeart> createState() => _AnimatedHeartState();
}

class _AnimatedHeartState extends State<AnimatedHeart> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: widget.animation == HeartAnimation.dropIn
          ? const Duration(milliseconds: 1500)
          : const Duration(milliseconds: 900),
    );
    Future.delayed(widget.delay, _play);
  }

  void _play() {
    if (!mounted) return;
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 1; // accessibility: no motion, just show the heart
      return;
    }
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;

    final heart = AnimatedBuilder(
      animation: _c,
      child: Icon(Icons.favorite, size: s, color: widget.color),
      builder: (context, child) {
        final t = _c.value;
        double dy;
        double scale;
        double opacity = 1;

        if (widget.animation == HeartAnimation.dropIn) {
          // 0 - 70%: fall from above with a natural bounce, fading in
          final fall = Curves.bounceOut.transform(const Interval(0.0, 0.7).transform(t));
          dy = -(1 - fall) * s * 1.6;
          opacity = const Interval(0.0, 0.2).transform(t);
          // 70 - 100%: one little heartbeat, then rest
          scale = 1 + 0.25 * math.sin(math.pi * const Interval(0.7, 1.0).transform(t));
        } else {
          const upPart = 0.35;
          if (t < upPart) {
            // jump up
            dy = -s * 0.9 * Curves.easeOut.transform(t / upPart);
          } else {
            // come down and bounce once
            final x = (t - upPart) / (1 - upPart);
            dy = -s * 0.9 * (1 - Curves.bounceOut.transform(x));
          }
          // small squash-pop as it lands
          scale = 1 + 0.2 * math.sin(math.pi * const Interval(0.8, 1.0).transform(t));
        }

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
    );

    if (!widget.replayOnTap) return heart;
    return GestureDetector(onTap: () => _c.forward(from: 0), child: heart);
  }
}
