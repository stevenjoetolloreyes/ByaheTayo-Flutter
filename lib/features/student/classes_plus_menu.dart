// Classes "+" menu (Feature 1 of the Classes + menu build, Nov 10,
// 2026): the floating menu opened by the round + button on the
// Classes & Timetable screen.
//
// Three options, in this order: Set Schedule Manual, Files, Google
// Schedule. Each option is a callback hook (onManual / onFiles /
// onGoogle) that Features 2-4 fill in; when a callback is not
// provided, tapping the option simply closes the menu (via
// onDismiss) — no fake flows, no placeholder screens.
//
// The menu owns no state: the parent owns the open/close state and
// drives [animation] (0 = closed, 1 = open). The spring
// overshoot/wobble comes from the parent's SpringSimulation; this
// widget only maps the animation value onto a rise + scale for the
// panel and a staggered fade/rise per option. With reduced motion
// the parent jumps the animation straight to 0/1, so everything
// here shows/hides instantly.
import 'package:flutter/material.dart';

/// The three destinations of the Classes "+" menu, in menu order.
enum ClassesPlusOption { manual, files, google }

/// Floating "+" menu for the Classes & Timetable screen.
///
/// Dark emerald style (bg #0c1410, brand #16A34A), Material icons,
/// English labels. The parent positions this widget above the round
/// + button and drives [animation]; tapping an option invokes its
/// hook (if provided) and then [onDismiss] so the parent can close
/// the menu.
class ClassesPlusMenu extends StatelessWidget {
  const ClassesPlusMenu({
    super.key,
    required this.animation,
    this.onManual,
    this.onFiles,
    this.onGoogle,
    this.onDismiss,
  });

  /// 0 = closed, 1 = open. Driven by the parent's controller; may
  /// briefly exceed 1 during the spring overshoot.
  final Animation<double> animation;

  /// Hooks for Features 2-4. Null = tapping the option just closes.
  final VoidCallback? onManual;
  final VoidCallback? onFiles;
  final VoidCallback? onGoogle;

  /// Called after any option tap so the parent can close the menu.
  final VoidCallback? onDismiss;

  static const _options =
      <({ClassesPlusOption option, IconData icon, String label, Key key})>[
        (
          option: ClassesPlusOption.manual,
          icon: Icons.edit_calendar_outlined,
          label: 'Set Schedule Manual',
          key: Key('classes-plus-option-manual'),
        ),
        (
          option: ClassesPlusOption.files,
          icon: Icons.folder_open,
          label: 'Files',
          key: Key('classes-plus-option-files'),
        ),
        (
          option: ClassesPlusOption.google,
          icon: Icons.calendar_month,
          label: 'Google Schedule',
          key: Key('classes-plus-option-google'),
        ),
      ];

  VoidCallback? _hookFor(ClassesPlusOption option) {
    return switch (option) {
      ClassesPlusOption.manual => onManual,
      ClassesPlusOption.files => onFiles,
      ClassesPlusOption.google => onGoogle,
    };
  }

  /// Staggered entrance per option: option [index] fades/rises in
  /// over its slice of the parent animation, ease-out. A pure
  /// function of the animation value, so reduced motion (parent
  /// jumps the value to 1) shows every option instantly.
  double _stagger(int index, double t) {
    final start = 0.15 + index * 0.18;
    final end = 0.55 + index * 0.18;
    final v = ((t - start) / (end - start)).clamp(0.0, 1.0);
    return Curves.easeOut.transform(v);
  }

  @override
  Widget build(BuildContext context) {
    // The panel and its rows are built inside the builder (not as
    // AnimatedBuilder's static child) because the rows' staggered
    // entrance depends on the live animation value.
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value;
        return Opacity(
          opacity: t.clamp(0.0, 1.0),
          child: Transform.translate(
            // Rises from below the + button; the spring overshoot
            // (t > 1) carries it a touch past its resting spot,
            // then it settles back.
            offset: Offset(0, 24 * (1 - t)),
            child: Transform.scale(
              scale: 0.92 + 0.08 * t,
              alignment: Alignment.bottomRight,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  key: const Key('classes-plus-menu'),
                  width: 248,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0C1410),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < _options.length; i++)
                        _PlusMenuRow(
                          option: _options[i],
                          progress: _stagger(i, t),
                          onTap: () {
                            _hookFor(_options[i].option)?.call();
                            onDismiss?.call();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One tappable menu row: Material icon + English label. [progress]
/// (0-1) is the row's staggered entrance; the row itself is a plain
/// StatelessWidget so the parent's AnimatedBuilder drives it.
class _PlusMenuRow extends StatelessWidget {
  const _PlusMenuRow({
    required this.option,
    required this.progress,
    required this.onTap,
  });

  final ({ClassesPlusOption option, IconData icon, String label, Key key})
  option;
  final double progress;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: progress,
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - progress)),
        child: InkWell(
          key: option.key,
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(option.icon, color: const Color(0xFF16A34A), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    option.label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
