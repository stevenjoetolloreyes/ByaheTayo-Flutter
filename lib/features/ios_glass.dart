// iPhone-only Glassmorphism styling tokens + components.
//
// SCOPE: iPhone/iOS ONLY. Android keeps its existing Material 3
// untouched — every call site branches on [iosGlassEnabled], which
// is false on Android, on web, and on the Linux widget-test host
// unless a test sets [iosGlassTestOverride].
//
// This file changes APPEARANCE only: same screens, same layout,
// same 6 tabs in the same order, same icons/labels/destinations,
// same tap behavior. No schema changes, no business-logic changes,
// no duplicated nav/wallet components — the shell reuses its one
// destinations list and passes it into [GlassBottomNav].
//
// DESIGN (approved direction): deep emerald #14532D background,
// frosted translucent glass cards (real BackdropFilter blur),
// thin glowing green-white borders, rounded glass surfaces, soft
// shadows, white high-contrast text, emerald accent. No excessive
// neon, no heavy transparency: glass fill stays at 12% white so
// text stays readable over the emerald gradient.
//
// iOS typography: glass surfaces render text with the SF Pro
// family (`.SF Pro Text`), which iOS resolves to the system font.
// On any other platform this styling never applies, so the family
// string is never resolved there.
import 'dart:io' show Platform;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Test hook only. Null (default) = real platform detection.
/// Widget tests set this to true/false and reset it in tearDown;
/// production code never sets it.
bool? iosGlassTestOverride;

/// True only on a real iOS device (or when a test forces it).
/// False on Android, web, macOS, and the test host.
bool get iosGlassEnabled {
  final override = iosGlassTestOverride;
  if (override != null) return override;
  if (kIsWeb) return false;
  return Platform.isIOS;
}

/// Deep emerald page background (approved #14532D at the top,
/// darkening toward the bottom so glass cards stay legible).
abstract final class IosGlassColors {
  static const Color backgroundTop = Color(0xFF14532D);
  static const Color backgroundBottom = Color(0xFF0A2E1A);
  static const Color accent = Color(0xFF16A34A);
  static const Color accentGlow = Color(0xFF22C55E);
}

/// Frosted glass surface geometry.
abstract final class IosGlassMetrics {
  static const double cardRadius = 24;
  static const double cardBlur = 20;
  static const double navBlur = 24;
  static const double navItemMinHeight = 64;
}

/// Full-page emerald gradient behind glass surfaces. The child
/// keeps its own padding; this only paints the background.
class IosGlassBackground extends StatelessWidget {
  const IosGlassBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            IosGlassColors.backgroundTop,
            IosGlassColors.backgroundBottom,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: child,
    );
  }
}

/// One frosted glass card: real blur over whatever is behind it,
/// translucent white fill, thin light border, soft shadow, white
/// high-contrast text (SF Pro on iOS) inherited by children that
/// do not set their own color.
class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius:
          BorderRadius.circular(IosGlassMetrics.cardRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: IosGlassMetrics.cardBlur,
          sigmaY: IosGlassMetrics.cardBlur,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius:
                BorderRadius.circular(IosGlassMetrics.cardRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.28),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          // Transparent Material INSIDE the frosted background so
          // ListTile/InkWell ink paints above the glass fill instead
          // of being hidden behind it (Flutter asserts otherwise).
          child: Material(
            type: MaterialType.transparency,
            child: DefaultTextStyle.merge(
              style: const TextStyle(
                color: Colors.white,
                fontFamily: '.SF Pro Text',
              ),
              child: IconTheme.merge(
                data: const IconThemeData(color: Colors.white),
                child: Padding(
                  padding: padding ?? const EdgeInsets.all(16),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Theme overrides for Material list content placed on glass:
/// white titles/subtitles/icons and a faint divider, so ListTiles
/// built for the light/dark themes stay readable on emerald.
class GlassListTheme extends StatelessWidget {
  const GlassListTheme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        listTileTheme: const ListTileThemeData(
          titleTextStyle: TextStyle(color: Colors.white),
          subtitleTextStyle: TextStyle(color: Colors.white70),
          iconColor: Colors.white,
        ),
        dividerTheme: DividerThemeData(
          color: Colors.white.withValues(alpha: 0.2),
        ),
      ),
      child: child,
    );
  }
}

/// One destination for [GlassBottomNav]. The shell maps its own
/// destinations list into these — same labels, icons, order.
class GlassNavDestination {
  const GlassNavDestination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// iPhone glass bottom navigation: the SAME 6 tabs in the SAME
/// order with the SAME icons/labels/destinations as the Material
/// NavigationBar — only the appearance changes (frosted bar,
/// thin glass top border, soft emerald glow on the active tab).
/// Tap targets are 56dp tall (above the 44pt iOS minimum) and the
/// bar extends through the home-indicator area.
class GlassBottomNav extends StatelessWidget {
  const GlassBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final List<GlassNavDestination> destinations;

  @override
  Widget build(BuildContext context) {
    // viewPadding (not padding): Scaffold never consumes it, so the
    // home-indicator inset is reliable here.
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: IosGlassMetrics.navBlur,
          sigmaY: IosGlassMetrics.navBlur,
        ),
        child: Container(
          key: const Key('glass-nav'),
          decoration: BoxDecoration(
            color: IosGlassColors.backgroundTop.withValues(alpha: 0.72),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.22),
              ),
            ),
          ),
          padding: EdgeInsets.only(
            top: 8,
            bottom: bottomInset > 0 ? bottomInset : 8,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 0; i < destinations.length; i++)
                Expanded(
                  child: _navItem(destinations[i], i == selectedIndex,
                      () => onSelect(i)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem(
      GlassNavDestination destination, bool selected, VoidCallback onTap) {
    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      fontFamily: '.SF Pro Text',
      color: selected ? Colors.white : Colors.white70,
    );
    final icon = Icon(
      selected ? destination.selectedIcon : destination.icon,
      size: 24,
      color: selected ? Colors.white : Colors.white70,
    );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(height: 4),
        Text(destination.label, style: labelStyle),
      ],
    );
    return Material(
      key: Key('glass-nav-item-${destination.label}'),
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          height: IosGlassMetrics.navItemMinHeight,
          child: Center(
            child: selected
                ? Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          IosGlassColors.accent.withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: IosGlassColors.accentGlow
                              .withValues(alpha: 0.45),
                          blurRadius: 16,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: content,
                  )
                : content,
          ),
        ),
      ),
    );
  }
}
