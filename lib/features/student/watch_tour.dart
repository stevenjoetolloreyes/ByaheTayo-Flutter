// Watch demo guided tour (Feature 3) — overlay-only tour of the
// Student tab.
//
// The tour never changes the Student tab: it highlights the real
// cards in place (pulsing emerald ring + spotlight dim) and shows a
// short caption bubble at each stop. Each stop lasts ~2.5s once it
// is on screen, then advances automatically. Controls: Back,
// Play/Pause, Next, End. Tapping the highlighted feature advances
// to the next stop. Ending (End, or finishing the last stop)
// dismisses the overlay and leaves the tab untouched.
//
// STOP LIST — 9 stops, NOT 11: the spec's stops 7 (My Notes) and
// 8 (Tasks) have no card on the real Student tab — the Tasks &
// Assignments card was removed Nov 8 at Steven's request and the
// Notes flow lives in the Study tab (Flashcards / Quiz), not here.
// Adding cards back just to fit the tour would break the
// "keep the tab exactly as-is" rule, so those two stops are
// skipped and the counter reads "N of 9".
//
// TARGETS: every stop resolves through a GlobalKey registered on
// [WatchTourController]. StudentTab registers its cards (and owns
// the scroll-into-view sweep — see [WatchTourController.revealTarget]);
// the shell registers the top nav (phone) / left sidebar (tablet)
// under the same 'nav' stop id, and renders this overlay above the
// whole shell so stop 1 can be highlighted. Targets below the fold
// are scrolled into view before highlighting; a target that never
// resolves still shows its caption (centred) so the tour keeps
// moving instead of stalling.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../minecraft_theme.dart';

/// One tour stop: the feature's id (matches a registered target
/// key), its short title, and the caption shown in the bubble.
class WatchTourStop {
  const WatchTourStop({
    required this.id,
    required this.title,
    required this.caption,
  });

  /// Matches the GlobalKey registered for this stop's widget.
  final String id;

  /// Short title shown in the caption bubble.
  final String title;

  /// One or two sentences explaining the feature.
  final String caption;
}

/// The tour's stops, in the order they are shown. Stop ids:
///
/// * `nav` — the shell's top nav (phone) / left sidebar (tablet),
///   registered by the shell, not by the tab.
/// * the rest — Student tab cards, registered by [StudentTab].
const List<WatchTourStop> kWatchTourStops = [
  WatchTourStop(
    id: 'nav',
    title: 'Switch tabs',
    caption: 'Use the icons up here to switch between Student, Study, '
        'Fares, Map, Communities and Account. On a tablet these live '
        'in the left sidebar instead.',
  ),
  WatchTourStop(
    id: 'walking',
    title: 'Walking Goal',
    caption: 'Your daily steps count here. Walk more to earn points '
        'toward rewards.',
  ),
  WatchTourStop(
    id: 'signin',
    title: '7-Day Sign-in',
    caption: 'Check in every day to build your streak and earn points.',
  ),
  WatchTourStop(
    id: 'verse',
    title: 'Verse of the Day',
    caption: 'A daily Bible verse to start your day. Tap the card to '
        'read more.',
  ),
  WatchTourStop(
    id: 'classes',
    title: 'Classes & Timetable',
    caption: "Today's classes and your full week timetable, all in "
        'one place.',
  ),
  WatchTourStop(
    id: 'allowance',
    title: 'Allowance & Budgeting',
    caption: 'Track your allowance, spending and savings goals here.',
  ),
  WatchTourStop(
    id: 'calendar',
    title: 'School Calendar',
    caption: 'School days, holidays and events for your school. Tap '
        'Edit to add your own days.',
  ),
  WatchTourStop(
    id: 'rewards',
    title: 'Rewards Center',
    caption: 'Spend your points and credits on rewards, and scan to '
        'earn more.',
  ),
  WatchTourStop(
    id: 'quotes',
    title: 'Daily Quotes',
    caption: 'A new motivational quote every day. Tap the heart to '
        'save your favorites.',
  ),
];

/// How long a stop stays on screen before auto-advancing, once the
/// stop is actually shown (the overlay restarts the clock after
/// each reveal — scrolling a below-the-fold target into view does
/// not eat into the dwell time).
const Duration kWatchTourStopDuration = Duration(milliseconds: 2500);

/// Owns the Watch demo tour state: which stop is showing, whether
/// the tour is running / paused, and the registry of target keys.
///
/// The controller is deliberately view-agnostic: the shell owns one
/// instance, passes it to the Student tab, and renders
/// [WatchTourOverlay] above the whole shell. A bare StudentTab (no
/// controller passed in) owns its own instance and renders the
/// overlay itself — same controller, same behaviour, minus the
/// shell's nav target.
class WatchTourController extends ChangeNotifier {
  /// The stops, in tour order.
  List<WatchTourStop> get stops => kWatchTourStops;

  bool _active = false;

  /// True while the tour overlay is up.
  bool get isActive => _active;

  int _currentIndex = 0;

  /// Index of the stop currently showing (0-based).
  int get currentIndex => _currentIndex;

  /// The stop currently showing.
  WatchTourStop get currentStop => stops[_currentIndex];

  /// 1-based stop number for the "N of 9" caption.
  int get currentNumber => _currentIndex + 1;

  /// True on the last stop (Next / auto-advance ends the tour).
  bool get isLastStop => _currentIndex >= stops.length - 1;

  bool _playing = true;

  /// True while the auto-advance clock is running. Pausing stops
  /// the clock; resuming restarts the full dwell for the stop.
  bool get isPlaying => _playing;

  Timer? _advanceTimer;

  /// Target keys by stop id. Several keys may share one id (the
  /// shell registers both the phone top nav and the tablet sidebar
  /// under 'nav'); the first one that is currently laid out wins.
  final Map<String, List<GlobalKey>> _targets = {};

  /// Scrolls [key]'s widget into view before the overlay measures
  /// it. Set by the Student tab: its ListView builds lazily, so a
  /// below-the-fold target has no context until it is scrolled
  /// into range — [Scrollable.ensureVisible] alone throws on an
  /// unbuilt target, so the tab sweeps its own ScrollController
  /// until the target builds, then ensures it visible. Null when
  /// no reveal hook is registered (the nav target is always
  /// visible, so it never needs one).
  Future<void> Function(GlobalKey key)? revealTarget;

  /// Registers [key] as the target for stop [id]. Safe to call
  /// more than once with the same key (no duplicates).
  void registerTarget(String id, GlobalKey key) {
    final keys = _targets.putIfAbsent(id, () => <GlobalKey>[]);
    if (!keys.contains(key)) keys.add(key);
  }

  /// Removes a previously registered target key.
  void unregisterTarget(String id, GlobalKey key) {
    final keys = _targets[id];
    if (keys == null) return;
    keys.remove(key);
    if (keys.isEmpty) _targets.remove(id);
  }

  /// The first registered key for [id] whose widget is currently
  /// laid out, or null when none is (below the fold, or the shell
  /// target in a bare-tab test).
  GlobalKey? targetKeyFor(String id) {
    final keys = _targets[id];
    if (keys == null) return null;
    for (final key in keys) {
      if (key.currentContext != null) return key;
    }
    return null;
  }

  /// Any registered key for [id], laid out or not — the reveal
  /// hook needs a key object for an unbuilt target so the tab can
  /// sweep its list toward it. Null when nothing is registered.
  GlobalKey? anyTargetKeyFor(String id) {
    final keys = _targets[id];
    if (keys == null || keys.isEmpty) return null;
    return keys.first;
  }

  /// Starts the tour on the first stop. No-op when already active
  /// (so a double tap on "Watch demo" cannot restart it mid-run).
  /// The auto-advance clock starts only once the overlay has
  /// revealed the stop — see [markStopShown].
  void start() {
    if (_active) return;
    _active = true;
    _currentIndex = 0;
    _playing = true;
    _stopClock();
    notifyListeners();
  }

  /// Ends the tour and dismisses the overlay. The Student tab is
  /// left exactly as it was — the overlay never touches it.
  void end() {
    if (!_active) return;
    _active = false;
    _currentIndex = 0;
    _playing = true;
    _stopClock();
    notifyListeners();
  }

  /// Advances to the next stop; ends the tour after the last stop.
  void next() {
    if (!_active) return;
    if (isLastStop) {
      end();
      return;
    }
    _currentIndex++;
    _stopClock();
    notifyListeners();
  }

  /// Goes back one stop. Stays on the first stop.
  void previous() {
    if (!_active || _currentIndex == 0) return;
    _currentIndex--;
    _stopClock();
    notifyListeners();
  }

  /// Tapping the highlighted feature advances, same as Next.
  void advanceOnTargetTap() => next();

  /// Pauses / resumes the auto-advance clock. Resuming restarts
  /// the full dwell for the current stop.
  void togglePlayPause() {
    if (!_active) return;
    _playing = !_playing;
    if (_playing) {
      _startClock();
    } else {
      _stopClock();
    }
    notifyListeners();
  }

  /// Called by the overlay once the current stop is revealed on
  /// screen (scrolled into view + measured). Restarts the
  /// auto-advance clock so the dwell counts from when the stop is
  /// actually visible. No-op while paused or inactive.
  void markStopShown() {
    if (!_active || !_playing) return;
    _startClock();
  }

  void _startClock() {
    _stopClock();
    _advanceTimer = Timer(kWatchTourStopDuration, () {
      if (!_active || !_playing) return;
      next();
    });
  }

  void _stopClock() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
  }

  @override
  void dispose() {
    _stopClock();
    super.dispose();
  }
}

/// The tour overlay: spotlight dim + pulsing emerald highlight ring
/// around the current stop's target, caption bubble, and controls.
///
/// Rendered above the shell (real app) or above the Student tab's
/// list (bare tab / tests) — either way it measures the target in
/// its own coordinate space, so it works wherever the Stack sits.
/// Invisible (zero-size) while the tour is inactive.
class WatchTourOverlay extends StatefulWidget {
  const WatchTourOverlay({super.key, required this.controller});

  final WatchTourController controller;

  @override
  State<WatchTourOverlay> createState() => _WatchTourOverlayState();
}

class _WatchTourOverlayState extends State<WatchTourOverlay>
    with SingleTickerProviderStateMixin {
  static const _emerald = MinecraftColors.deepLeaves;
  static const _emeraldAccent = MinecraftColors.grassGreen;
  static const _darkBg = MinecraftColors.darkBackground;

  /// The current target's rect in this overlay's coordinates, or
  /// null when the target is not laid out (caption centres instead).
  Rect? _targetRect;

  /// Monotonic guard: a reveal started for one stop must not
  /// overwrite the rect after the tour moved on.
  int _revealGeneration = 0;

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTourChanged);
    // The pulse must NOT run while the tour is inactive: a
    // repeating controller schedules frames forever, so any test
    // pumping this tab with pumpAndSettle would never settle.
    if (widget.controller.isActive) {
      _pulse.repeat(reverse: true);
      _scheduleReveal();
    }
  }

  @override
  void didUpdateWidget(covariant WatchTourOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTourChanged);
      widget.controller.addListener(_onTourChanged);
      _scheduleReveal();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTourChanged);
    _pulse.dispose();
    super.dispose();
  }

  void _onTourChanged() {
    if (!mounted) return;
    if (!widget.controller.isActive) {
      // Stop the pulse when the tour ends (see initState): a
      // repeating controller would keep scheduling frames forever.
      _pulse.stop();
      setState(() => _targetRect = null);
      return;
    }
    if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    _scheduleReveal();
  }

  void _scheduleReveal() {
    final generation = ++_revealGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _revealGeneration) _revealCurrentStop();
    });
  }

  /// Scrolls the current stop's target into view, measures it in
  /// this overlay's coordinates, then starts the dwell clock.
  /// A missing target leaves [_targetRect] null — the caption
  /// bubble centres and the tour keeps moving.
  Future<void> _revealCurrentStop() async {
    if (!mounted || !widget.controller.isActive) return;
    final generation = _revealGeneration;
    // Capture this overlay's own RenderBox before any await: the
    // target rect is measured against it afterwards.
    final overlayBox = context.findRenderObject() as RenderBox?;
    final stop = widget.controller.currentStop;
    final reveal = widget.controller.revealTarget;
    var key = widget.controller.targetKeyFor(stop.id);
    // Below-the-fold tab targets have no context until scrolled
    // into range; the tab's reveal hook sweeps its list until the
    // target builds (or gives up). Re-read the key afterwards —
    // the sweep may have built it.
    if (key == null && reveal != null) {
      final anyKey = widget.controller.anyTargetKeyFor(stop.id);
      if (anyKey != null) {
        await reveal(anyKey);
        if (!mounted || generation != _revealGeneration) return;
        key = widget.controller.targetKeyFor(stop.id);
      }
    }
    Rect? rect;
    if (mounted && generation == _revealGeneration) {
      rect = _measureTarget(key, overlayBox);
    }
    if (!mounted || generation != _revealGeneration) return;
    setState(() => _targetRect = rect);
    widget.controller.markStopShown();
  }

  /// Measures [key]'s widget in this overlay's coordinates.
  /// Synchronous helper (no await inside) so no BuildContext is
  /// ever used across an async gap: the context is read fresh from
  /// the key, and a null / unlaid-out target yields null.
  Rect? _measureTarget(GlobalKey? key, RenderBox? overlayBox) {
    final targetContext = key?.currentContext;
    if (targetContext == null || overlayBox == null) return null;
    final box = targetContext.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlayBox);
    return (topLeft & box.size).inflate(6);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.isActive) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        if (!widget.controller.isActive) return const SizedBox.shrink();
        final stop = widget.controller.currentStop;
        return Positioned.fill(
          child: Stack(
            children: [
              _buildDim(),
              if (_targetRect != null) _buildHighlight(),
              _buildCaption(stop),
              _buildControls(),
            ],
          ),
        );
      },
    );
  }

  /// Spotlight dim: four panels around the highlight hole (or one
  /// full panel when there is no target). The panels absorb taps so
  /// the tour is modal — nothing underneath can be tapped except
  /// the highlighted feature itself.
  Widget _buildDim() {
    const dim = Color(0xB3000000);
    final rect = _targetRect;
    if (rect == null) {
      return Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {},
          child: const ColoredBox(color: dim),
        ),
      );
    }
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: math.max(0, rect.top),
          child: _dimPanel(dim),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: rect.bottom,
          bottom: 0,
          child: _dimPanel(dim),
        ),
        Positioned(
          left: 0,
          top: rect.top,
          width: math.max(0, rect.left),
          height: rect.height,
          child: _dimPanel(dim),
        ),
        Positioned(
          left: rect.right,
          right: 0,
          top: rect.top,
          height: rect.height,
          child: _dimPanel(dim),
        ),
      ],
    );
  }

  Widget _dimPanel(Color color) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ColoredBox(color: color),
    );
  }

  /// Pulsing emerald ring around the target. Tapping it advances.
  Widget _buildHighlight() {
    final rect = _targetRect!;
    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: GestureDetector(
        key: const ValueKey('watch-tour-highlight'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.controller.advanceOnTargetTap,
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final t = _pulse.value;
            return Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _emeraldAccent.withValues(
                    alpha: 0.65 + 0.35 * t,
                  ),
                  width: 2.5 + t,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _emeraldAccent.withValues(alpha: 0.25 + 0.3 * t),
                    blurRadius: 10 + 10 * t,
                    spreadRadius: 2 * t,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Caption bubble: "N of 9 · How to use" + title + caption.
  /// Below the target when there is room, above it otherwise; when
  /// there is no target (unbuilt / shell-only stop in a bare tab)
  /// it centres on screen.
  Widget _buildCaption(WatchTourStop stop) {
    final controller = widget.controller;
    final size = MediaQuery.sizeOf(context);
    final rect = _targetRect;
    const bubbleHeight = 132.0;
    const controlsHeight = 96.0;
    double top;
    if (rect == null) {
      top = (size.height - bubbleHeight) / 2;
    } else if (rect.bottom + 12 + bubbleHeight <
        size.height - controlsHeight) {
      top = rect.bottom + 12;
    } else {
      top = math.max(8, rect.top - 12 - bubbleHeight);
    }
    return Positioned(
      key: const ValueKey('watch-tour-caption'),
      left: 16,
      right: 16,
      top: top,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
          decoration: BoxDecoration(
            color: _darkBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _emeraldAccent, width: 1.5),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${controller.currentNumber} of ${controller.stops.length} · How to use',
                style: const TextStyle(
                  color: _emeraldAccent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                stop.title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                stop.caption,
                style: const TextStyle(
                  color: Color(0xFFD1D5DB),
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Back / Play-Pause / Next / End, in a dark emerald pill pinned
  /// above the bottom safe area.
  Widget _buildControls() {
    final controller = widget.controller;
    final isFirst = controller.currentIndex == 0;
    return Positioned(
      left: 16,
      right: 16,
      bottom: MediaQuery.paddingOf(context).bottom + 16,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: _emerald,
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                color: Color(0x66000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              IconButton(
                key: const ValueKey('watch-tour-back'),
                onPressed: isFirst ? null : controller.previous,
                icon: const Icon(Icons.chevron_left),
                color: Colors.white,
                disabledColor: Colors.white38,
                tooltip: 'Back',
              ),
              IconButton(
                key: const ValueKey('watch-tour-play-pause'),
                onPressed: controller.togglePlayPause,
                icon: Icon(
                  controller.isPlaying ? Icons.pause : Icons.play_arrow,
                ),
                color: Colors.white,
                tooltip: controller.isPlaying ? 'Pause' : 'Play',
              ),
              IconButton(
                key: const ValueKey('watch-tour-next'),
                onPressed: controller.next,
                icon: const Icon(Icons.chevron_right),
                color: Colors.white,
                tooltip: 'Next',
              ),
              const Spacer(),
              TextButton.icon(
                key: const ValueKey('watch-tour-end'),
                onPressed: controller.end,
                icon: const Icon(Icons.close, size: 18),
                label: const Text('End'),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
