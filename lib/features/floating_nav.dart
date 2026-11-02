import 'dart:ui';

import 'package:flutter/material.dart';

/// One destination for [FloatingGlassNav]. The shell maps its own
/// destinations list into these — same labels, icons, order.
class FloatingNavDestination {
  const FloatingNavDestination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Android Material 3 floating dark-glass bottom navigation: the SAME
/// 6 tabs in the SAME order with the SAME icons/labels/destinations
/// as the old Material NavigationBar — only the bar changes.
///
/// The bar is a capsule that floats above the bottom edge (16dp side
/// margins, 12dp + system-inset bottom margin) instead of docking to
/// it. Frosted blur, a thin reflective border plus a glossy top-edge
/// highlight line, and a soft drop shadow give it depth. The active
/// tab is an individual rounded glass pill (white icon + label over
/// a subtle emerald glass highlight); inactive tabs are muted gray.
/// The pill and the label animate on every tab change (~250ms).
///
/// Light + dark: the capsule is dark charcoal in both modes (the
/// spec's glass), slightly more opaque on light backgrounds so it
/// stays legible, slightly more transparent on dark ones.
///
/// Deliberately NOT a full-width docked bar and NOT extendBody: the
/// body still ends above the bar, so no screen content is ever hidden
/// behind the capsule.
class FloatingGlassNav extends StatelessWidget {
  const FloatingGlassNav({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<FloatingNavDestination> destinations;

  static const _emerald = Color(0xFF14532D);
  static const _charcoal = Color(0xFF1F1F1F);

  @override
  Widget build(BuildContext context) {
    // viewPadding (not padding): Scaffold never consumes it, so the
    // gesture-bar / cutout insets are reliable here.
    final viewPadding = MediaQuery.viewPaddingOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      key: const Key('floating-nav'),
      margin: EdgeInsets.only(
        left: 16 + viewPadding.left,
        right: 16 + viewPadding.right,
        bottom: 12 + viewPadding.bottom,
      ),
      // Shadow lives OUTSIDE the ClipRRect: a shadow painted inside
      // it would be clipped to the capsule shape.
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? 0.45 : 0.30),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            key: const Key('floating-nav-capsule'),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(36),
              gradient: LinearGradient(
                colors: [
                  _charcoal.withValues(alpha: dark ? 0.70 : 0.85),
                  _charcoal.withValues(alpha: dark ? 0.78 : 0.90),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              // Layer 1 of the reflective border: a thin hairline
              // all around; the glossy top highlight line below is
              // layer 2.
              border: Border.all(
                color: Colors.white.withValues(alpha: dark ? 0.30 : 0.22),
                width: 1,
              ),
            ),
            child: Stack(
              children: [
                // Glossy top-edge highlight: bright at the center,
                // fading to transparent at both ends, inset so it
                // reads as a light streak rather than a full border.
                Positioned(
                  top: 0,
                  left: 28,
                  right: 28,
                  child: Container(
                    height: 1,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.50),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Row(
                    children: [
                      for (int i = 0; i < destinations.length; i++)
                        Expanded(
                          child: _navItem(destinations[i], i == selectedIndex,
                              () => onSelect(i)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(
      FloatingNavDestination destination, bool selected, VoidCallback onTap) {
    final labelColor =
        selected ? Colors.white : Colors.white.withValues(alpha: 0.55);
    return Material(
      key: Key('floating-nav-item-${destination.label}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: selected
                ? LinearGradient(
                    colors: [
                      _emerald.withValues(alpha: 0.65),
                      _emerald.withValues(alpha: 0.40),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : null,
            border: selected
                ? Border.all(
                    color: Colors.white.withValues(alpha: 0.30),
                    width: 1,
                  )
                : null,
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: _emerald.withValues(alpha: 0.45),
                      blurRadius: 12,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 24,
                color: labelColor,
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      selected ? FontWeight.w700 : FontWeight.w500,
                  color: labelColor,
                ),
                // scaleDown (never wrap, never overflow): on a 320dp
                // phone each tab is ~50dp wide while "Communities"
                // at 11sp is wider — it shrinks slightly instead of
                // overflowing.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(destination.label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
