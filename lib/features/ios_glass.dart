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
// DESIGN (approved direction, refined Nov 2 from the user's glossy
// reference): vivid emerald background with flowing aurora light
// shapes, bright luminous glass cards (real BackdropFilter blur),
// strong top-edge highlights, rounded glass surfaces, soft
// shadows, white high-contrast text, emerald accent. The aurora
// shapes behind the cards are what make the glass read as glass:
// without something luminous to refract, the cards look like
// solid dark panels. Fills stay translucent enough that white
// text stays readable over the emerald background.
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
/// darkening toward the bottom so glass cards stay legible),
/// plus the luminous aurora greens that flow behind the glass.
abstract final class IosGlassColors {
  static const Color backgroundTop = Color(0xFF14532D);
  static const Color backgroundBottom = Color(0xFF0A2E1A);
  static const Color accent = Color(0xFF16A34A);
  static const Color accentGlow = Color(0xFF22C55E);

  /// Aurora light shapes (bright greens, used only as soft radial
  /// glows and the diagonal streak behind the cards).
  static const Color auroraBright = Color(0xFF4ADE80);
  static const Color auroraMid = Color(0xFF22C55E);
  static const Color auroraDeep = Color(0xFF16A34A);
}

/// Frosted glass surface geometry.
abstract final class IosGlassMetrics {
  static const double cardRadius = 24;
  static const double cardBlur = 28;
  static const double navBlur = 28;
  static const double navItemMinHeight = 64;
}

/// Full-page emerald gradient behind glass surfaces, with flowing
/// aurora light shapes (soft radial glows + one diagonal light
/// streak) layered between the gradient and the child. The child
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
      child: Stack(
        children: [
          // Aurora glows: luminous radial gradients with a bright
          // near-white core fading through green to transparent.
          // Kept strong on purpose: faint glows disappear behind
          // the glass and the cards read as solid panels.
          Positioned(
            top: -70,
            left: 0,
            right: 0,
            child: Center(
              child: _auroraBlob(
                300,
                IosGlassColors.auroraBright,
                0.70,
              ),
            ),
          ),
          Positioned(
            top: -90,
            right: -70,
            child: _auroraBlob(
              340,
              IosGlassColors.auroraBright,
              0.75,
            ),
          ),
          Positioned(
            top: 240,
            left: -110,
            child: _auroraBlob(
              380,
              IosGlassColors.auroraMid,
              0.65,
            ),
          ),
          Positioned(
            bottom: 140,
            right: -90,
            child: _auroraBlob(
              320,
              IosGlassColors.auroraDeep,
              0.70,
            ),
          ),
          // Diagonal light streak flowing across the page.
          Positioned.fill(
            child: Transform.rotate(
              angle: -0.5,
              child: Center(
                child: Container(
                  width: 900,
                  height: 220,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.0),
                        Colors.white.withValues(alpha: 0.16),
                        IosGlassColors.auroraBright
                            .withValues(alpha: 0.30),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.35, 0.55, 1.0],
                    ),
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }

  /// One luminous radial glow blob of [size] logical pixels:
  /// bright core, green mid, transparent edge.
  static Widget _auroraBlob(double size, Color color, double alpha) {
    final core = Color.lerp(color, Colors.white, 0.35)!;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [
            core.withValues(alpha: alpha),
            color.withValues(alpha: alpha * 0.6),
            color.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ),
      ),
    );
  }
}

/// One frosted glass card: real blur over whatever is behind it,
/// luminous gradient fill (brighter at the top, so light appears
/// to fall across the card), strong top-edge highlight, soft
/// shadow, white high-contrast text (SF Pro on iOS) inherited by
/// children that do not set their own color.
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
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.30),
                Colors.white.withValues(alpha: 0.14),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            borderRadius:
                BorderRadius.circular(IosGlassMetrics.cardRadius),
            // Uniform border color: Flutter asserts when a
            // borderRadius meets non-uniform side colors, so the
            // bright top edge is a highlight overlay below, not a
            // thicker top BorderSide.
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.20),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Transparent Material INSIDE the frosted background
              // so ListTile/InkWell ink paints above the glass fill
              // instead of being hidden behind it (Flutter asserts
              // otherwise).
              Material(
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
              // Glossy top-edge highlight: a bright line inset
              // from the corners, fading at both ends.
              Positioned(
                top: 0,
                left: 20,
                right: 20,
                child: Container(
                  height: 1.2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.0),
                        Colors.white.withValues(alpha: 0.70),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ],
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
/// NavigationBar — only the appearance changes (glossy frosted
/// bar, bright glass top border, bright green glow pill on the
/// active tab). Tap targets are 56dp tall (above the 44pt iOS
/// minimum) and the bar extends through the home-indicator area.
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
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.20),
                IosGlassColors.backgroundTop.withValues(alpha: 0.80),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.45),
                width: 1.0,
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
                      gradient: const LinearGradient(
                        colors: [
                          IosGlassColors.accentGlow,
                          IosGlassColors.accent,
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: IosGlassColors.accentGlow
                              .withValues(alpha: 0.65),
                          blurRadius: 20,
                          spreadRadius: 2,
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
