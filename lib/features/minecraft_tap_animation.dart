// Minecraft tap animations (Feature 5).
//
// A reusable wrapper that gives any tappable child the tap feedback
// from the approved preview artifact `estudyantego-minecraft-green-
// cartoon-design` (v3): a squash (scale 1 -> .94 -> 1.04 -> 1 over
// .28s with the preview's overshoot ease), an expanding square ring
// at the tap point, a burst of 6 pixel bits, and — for reward taps
// only — a rising music note.
//
// Visual-only: the wrapper never changes what a tap DOES. It has
// two modes, and in both the underlying action fires exactly once,
// exactly as before:
//
// * [onTap] provided: the wrapper owns the gesture (a
//   GestureDetector) and calls [onTap] once per tap. The child
//   should be a plain visual in this mode.
// * [onTap] null (default): the wrapper only OBSERVES pointer
//   events through a passive Listener and plays the animation;
//   the child's own InkWell / GestureDetector / button still owns
//   the tap, so wrapping an existing tappable cannot swallow,
//   delay, or double-fire it.
//
// Reduced motion: when MediaQuery.disableAnimations is true, the
// wrapper renders the child (plus a plain GestureDetector when it
// owns [onTap]) with no animation at all — taps show the finished
// state instantly.
//
// MAP TAB STAYS NORMAL: nothing in this file is applied to the Map
// tab. Sounds (Feature 6) play through [SplashSound]: the wrapper
// plays [sound] once per tap-down, in sync with the squash, in
// both modes — and also under reduced motion (sound is not motion,
// and sounds are always-on, per Steven's rule; there is no mute
// toggle). Disabled wrappers play no sound, since their tap does
// nothing.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'minecraft_theme.dart';
import 'onboarding/splash_sound.dart';

/// Minecraft tap feedback around any tappable child.
///
/// See the file header for the two modes ([onTap] owned vs.
/// observed) and the reduced-motion behavior.
class MinecraftTapAnimation extends StatefulWidget {
  const MinecraftTapAnimation({
    super.key,
    required this.child,
    this.onTap,
    this.reward = false,
    this.effects = true,
    this.enabled = true,
    this.sound = MinecraftSoundKind.click,
  });

  /// The visual to animate. In [onTap] mode this must be a plain
  /// visual (no gesture of its own); in observed mode it is the
  /// existing tappable, untouched.
  final Widget child;

  /// When provided, the wrapper owns the tap and calls this exactly
  /// once per tap. When null, the child's own gesture owns the tap
  /// and the wrapper only plays the animation.
  final VoidCallback? onTap;

  /// Reward taps (placing a class, forging a quiz, earning points):
  /// the ring is gold and a music note rises from the tap point.
  /// Ordinary taps get a grey ring and no note.
  final bool reward;

  /// Ring + pixel-bit burst (and the reward note). False keeps the
  /// squash only. Defaults to true.
  final bool effects;

  /// False renders the child with no animation at all (used for
  /// disabled buttons whose tap does nothing).
  final bool enabled;

  /// The Minecraft sound played once per tap (Feature 6), in sync
  /// with the squash. Defaults to [MinecraftSoundKind.click];
  /// callers pass the kind their tap maps to (pop for tabs /
  /// picker / quest rows / FAB, select for day toggles, levelup
  /// for Save, forge for 'Forge a Quiz', bell for the notification
  /// bell, like for Like). Best-effort: silence on failure, and
  /// the tap action never depends on audio.
  final MinecraftSoundKind sound;

  @override
  State<MinecraftTapAnimation> createState() => _MinecraftTapAnimationState();
}

class _MinecraftTapAnimationState extends State<MinecraftTapAnimation>
    with SingleTickerProviderStateMixin {
  /// Full effect timeline: squash .28s, ring .45s, bits .5s, note
  /// .7s — the preview's timings, driven by one 700ms controller
  /// with intervals below.
  static const _total = Duration(milliseconds: 700);

  /// The preview's overshoot ease, cubic-bezier(.34,1.56,.64,1).
  static const _overshoot = Cubic(0.34, 1.56, 0.64, 1.0);

  /// Pixel-bit colors from the preview: grass, gold, emerald,
  /// dirt, sky — the 6th bit repeats grass.
  static const _bitColors = <Color>[
    MinecraftColors.grassGreen,
    MinecraftColors.gold,
    MinecraftColors.emerald,
    MinecraftColors.dirtBrown,
    MinecraftColors.skyBlue,
    MinecraftColors.grassGreen,
  ];

  late final AnimationController _controller;

  /// Squash: 1 -> .94 (80ms) -> 1.04 (100ms) -> 1 (100ms), i.e.
  /// the first 280ms of the timeline.
  late final Animation<double> _squash;

  /// Ring: 14 -> 54px, rotating 0 -> 45deg, over the first 450ms.
  late final Animation<double> _ringSize;
  late final Animation<double> _ringRotation;
  late final Animation<double> _ringOpacity;

  /// Bits: burst outward over the first 500ms.
  late final Animation<double> _bitsProgress;
  late final Animation<double> _bitsOpacity;

  /// Note (reward only): rises 58px over the full 700ms.
  late final Animation<double> _noteRise;
  late final Animation<double> _noteOpacity;

  /// Tap point in the wrapper's local coordinates, or null when no
  /// effect is currently playing.
  Offset? _tapPoint;

  /// Per-tap burst directions: 6 roughly-even angles with jitter,
  /// 24-36px out (the preview's random +/-36px).
  var _bitOffsets = const <Offset>[];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _total)
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          // The effects unmount once the timeline finishes, so a
          // settled wrapper shows only the child.
          if (mounted) setState(() => _tapPoint = null);
        }
      });
    _squash =
        TweenSequence<double>([
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 1.0,
              end: 0.94,
            ).chain(CurveTween(curve: Curves.easeIn)),
            weight: 80,
          ),
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 0.94,
              end: 1.04,
            ).chain(CurveTween(curve: _overshoot)),
            weight: 100,
          ),
          TweenSequenceItem(
            tween: Tween<double>(
              begin: 1.04,
              end: 1.0,
            ).chain(CurveTween(curve: Curves.easeOut)),
            weight: 100,
          ),
        ]).animate(
          CurvedAnimation(parent: _controller, curve: Interval(0.0, 0.4)),
        );
    final ringInterval = CurvedAnimation(
      parent: _controller,
      curve: Interval(0.0, 450 / 700),
    );
    _ringSize = Tween<double>(
      begin: 14,
      end: 54,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(ringInterval);
    _ringRotation = Tween<double>(
      begin: 0,
      end: math.pi / 4,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(ringInterval);
    _ringOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 60),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 40),
    ]).animate(ringInterval);
    final bitsInterval = CurvedAnimation(
      parent: _controller,
      curve: Interval(0.0, 500 / 700),
    );
    _bitsProgress = Tween<double>(
      begin: 0,
      end: 1,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(bitsInterval);
    _bitsOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 60),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 40),
    ]).animate(bitsInterval);
    _noteRise = Tween<double>(
      begin: 0,
      end: 58,
    ).chain(CurveTween(curve: Curves.easeOut)).animate(_controller);
    _noteOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 50),
      TweenSequenceItem(tween: Tween<double>(begin: 1.0, end: 0.0), weight: 30),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(Offset localPosition) {
    // Sound + animation start together on pointer-down, in both
    // modes, exactly once per tap-down. (In owned mode the action
    // itself fires later, on tap-up, via [onTap]; in observed mode
    // the child's own gesture owns the tap.)
    SplashSound.play(widget.sound);
    setState(() {
      _tapPoint = localPosition;
      _bitOffsets = _burstOffsets();
    });
    _controller.forward(from: 0.0);
  }

  /// Sound only, for the reduced-motion paths below (no animation
  /// widgets exist there, but the tap still sounds).
  void _playSound() => SplashSound.play(widget.sound);

  List<Offset> _burstOffsets() {
    final random = math.Random();
    return List<Offset>.generate(6, (i) {
      final angle = i * math.pi / 3 + (random.nextDouble() - 0.5) * 0.7;
      final distance = 24 + random.nextDouble() * 12;
      return Offset(math.cos(angle) * distance, math.sin(angle) * distance);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion (or disabled): no animation widgets at all.
    // The tap still works — the wrapper owns [onTap] through a
    // plain GestureDetector, or the child's own gesture fires —
    // and the tap still sounds (sound is not motion). Disabled
    // wrappers play no sound, since their tap does nothing.
    if (!widget.enabled || MediaQuery.of(context).disableAnimations) {
      if (widget.onTap == null) {
        if (!widget.enabled) return widget.child;
        return Listener(
          onPointerDown: (_) => _playSound(),
          child: widget.child,
        );
      }
      return GestureDetector(
        onTap: () {
          // Reduced motion (enabled): the tap still sounds.
          // Disabled: no sound — the tap does nothing in use
          // (the underlying control is disabled too).
          if (widget.enabled) _playSound();
          widget.onTap!();
        },
        child: widget.child,
      );
    }

    final animated = AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Transform.scale(
              key: const Key('minecraft-tap-squash'),
              scale: _squash.value,
              child: widget.child,
            ),
            if (_tapPoint != null && widget.effects) ..._effectWidgets(),
          ],
        );
      },
    );

    // Owned-tap mode: the wrapper fires [onTap] itself.
    if (widget.onTap != null) {
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: (details) => _handleTapDown(details.localPosition),
        onTap: widget.onTap,
        child: animated,
      );
    }

    // Observed mode: a passive Listener only watches pointer-down
    // so the child's own gesture keeps owning the tap.
    return Listener(
      onPointerDown: (event) => _handleTapDown(event.localPosition),
      child: animated,
    );
  }

  List<Widget> _effectWidgets() {
    final point = _tapPoint!;
    // Ordinary taps: grey ring (readable in light and dark).
    // Reward taps: gold #E5A100, per the preview.
    final ringColor = widget.reward
        ? MinecraftColors.goldDark
        : MinecraftColors.stone;
    final ringSize = _ringSize.value;
    final widgets = <Widget>[
      Positioned(
        left: point.dx - ringSize / 2,
        top: point.dy - ringSize / 2,
        child: Transform.rotate(
          angle: _ringRotation.value,
          child: Container(
            key: const Key('minecraft-tap-ring'),
            width: ringSize,
            height: ringSize,
            decoration: BoxDecoration(
              border: Border.all(
                color: ringColor.withValues(alpha: _ringOpacity.value),
                width: 3,
              ),
            ),
          ),
        ),
      ),
    ];
    for (var i = 0; i < _bitOffsets.length; i++) {
      final offset = _bitOffsets[i] * _bitsProgress.value;
      widgets.add(
        Positioned(
          left: point.dx + offset.dx - 4.5,
          top: point.dy + offset.dy - 4.5,
          child: Opacity(
            opacity: _bitsOpacity.value,
            child: Container(
              key: Key('minecraft-tap-bit-$i'),
              width: 9,
              height: 9,
              color: _bitColors[i],
            ),
          ),
        ),
      );
    }
    if (widget.reward) {
      widgets.add(
        Positioned(
          left: point.dx - 10,
          top: point.dy - 10 - _noteRise.value,
          child: Opacity(
            opacity: _noteOpacity.value,
            child: Transform.rotate(
              // The preview's note tilts -8deg as it rises.
              angle: -8 * math.pi / 180,
              child: const Icon(
                Icons.music_note,
                key: Key('minecraft-tap-note'),
                color: MinecraftColors.goldDark,
                size: 20,
              ),
            ),
          ),
        ),
      );
    }
    return widgets;
  }
}
