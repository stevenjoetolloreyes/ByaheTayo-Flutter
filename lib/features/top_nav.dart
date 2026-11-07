// Facebook-style top navigation for phones (EstudyanteGO preview port).
//
// Icon-only, directly under the header. Text labels are kept as
// semantics labels + tooltips only — no visible text. The active tab
// gets an emerald highlight and a sliding indicator bar
// (AnimatedPositioned) under its icon.
//
// The six tabs share the full phone width evenly (LayoutBuilder):
// each tab gets exactly one sixth of the available width, so the
// icons spread edge to edge like the preview. The previous version
// used a fixed 64px-per-tab row (384px total) inside a horizontal
// scroll view, which left the icons clustered on the left with an
// empty gap on the right of wider phones.
//
// Wide layout (width >= 600) keeps the left sidebar instead; this
// widget is only used by the phone branch of the shell in main.dart.

import 'package:flutter/material.dart';

/// One destination for [TopNavBar]. The shell maps its own
/// destinations list into these — same labels, icons, order.
class TopNavDestination {
  const TopNavDestination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class TopNavBar extends StatelessWidget {
  const TopNavBar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<TopNavDestination> destinations;

  static const _deepEmerald = Color(0xFF14532D);
  static const _indicatorWidth = 28.0;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark ? const Color(0xFF34D399) : _deepEmerald;
    final inactiveColor = scheme.onSurfaceVariant;
    final clampedIndex =
        selectedIndex.clamp(0, destinations.length - 1);

    return Container(
      key: const Key('top-nav'),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(bottom: BorderSide(color: scheme.outline)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Equal shares of the available width — the row always
          // fills the phone, so the first icon sits near the left
          // edge and the last near the right edge, like the preview.
          final itemWidth =
              constraints.maxWidth / destinations.length;
          return SizedBox(
            height: 52,
            child: Stack(
              children: [
                Row(
                  children: [
                    for (int i = 0; i < destinations.length; i++)
                      _navItem(
                        context,
                        destinations[i],
                        i == clampedIndex,
                        activeColor,
                        inactiveColor,
                        itemWidth,
                        () => onSelect(i),
                      ),
                  ],
                ),
                // Sliding indicator: one bar that animates under the
                // active tab instead of appearing per-item. Its
                // position follows the same equal-share width, so it
                // stays centered under the active icon.
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  left: clampedIndex * itemWidth +
                      (itemWidth - _indicatorWidth) / 2,
                  bottom: 0,
                  width: _indicatorWidth,
                  height: 3,
                  child: Container(
                    decoration: BoxDecoration(
                      color: activeColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    TopNavDestination destination,
    bool selected,
    Color activeColor,
    Color inactiveColor,
    double itemWidth,
    VoidCallback onTap,
  ) {
    return SizedBox(
      width: itemWidth,
      height: 52,
      child: Tooltip(
        message: destination.label,
        child: Semantics(
          label: destination.label,
          button: true,
          selected: selected,
          child: Material(
            key: Key('top-nav-item-${destination.label}'),
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? activeColor.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 24,
                    color: selected ? activeColor : inactiveColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
