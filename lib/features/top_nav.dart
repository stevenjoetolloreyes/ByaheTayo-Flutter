// Facebook-style top navigation for phones (EstudyanteGO preview port),
// restyled with the Minecraft theme (Feature 1): grass-green blocky
// active pill, 3px ink bottom border.
//
// Icon-only, directly under the header. Text labels are kept as
// semantics labels + tooltips only — no visible text. The active tab
// gets a grass-green block pill (white icon, ink border).
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

import 'minecraft_tap_animation.dart';
import 'minecraft_theme.dart';
import 'onboarding/splash_sound.dart';

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark
        ? MinecraftColors.grassBright
        : MinecraftColors.grassGreen;
    final inactiveColor = scheme.onSurfaceVariant;
    final clampedIndex = selectedIndex.clamp(0, destinations.length - 1);

    return Container(
      key: const Key('top-nav'),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? scheme.outline : MinecraftColors.border,
            width: 3,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Equal shares of the available width — the row always
          // fills the phone, so the first icon sits near the left
          // edge and the last near the right edge, like the preview.
          final itemWidth = constraints.maxWidth / destinations.length;
          return SizedBox(
            height: 52,
            child: Row(
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
              // Feature 5: tap squash + ring/bits on the active
              // pill. The wrapper only observes the pointer; the
              // InkWell still owns the tab switch.
              // Feature 6: tabs play pop.
              child: Center(
                child: MinecraftTapAnimation(
                  sound: MinecraftSoundKind.pop,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      // Minecraft active state (Feature 1): a solid
                      // grass-green block pill with a white icon and a
                      // 2.5px ink chip border, 11px tab corners. The
                      // sliding bottom bar is gone (Nov 7). Same 52dp
                      // height, same equal shares.
                      color: selected ? activeColor : Colors.transparent,
                      borderRadius: BorderRadius.circular(
                        MinecraftShapes.tabRadius,
                      ),
                      border: selected ? MinecraftShapes.chipBorder : null,
                    ),
                    child: Icon(
                      selected ? destination.selectedIcon : destination.icon,
                      size: 24,
                      color: selected ? Colors.white : inactiveColor,
                    ),
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
