// Minecraft-green-cartoon theme foundation (Feature 1).
//
// Tokens + shared component styles from the approved preview artifact
// `estudyantego-minecraft-green-cartoon-design` (v3). Visual-only:
// this file owns colors, typography, borders, radii, and hard shadows
// — no functionality, data, navigation, or flows live here.
//
// Fonts come from the `google_fonts` package (Baloo 2 headings,
// Nunito body, Press Start 2P tiny pixel accents). They are downloaded
// at runtime, so NO binary font files are added to the repo (binary
// fonts cannot be pushed via the GitHub App). When the device is
// offline the first time a font is needed, Flutter falls back to the
// platform default font for that run and the downloaded font is used
// afterwards; the palette and geometry below never depend on the font.
//
// MAP TAB STAYS NORMAL: nothing in this file is applied to the Map tab.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'minecraft_tap_animation.dart';
import 'onboarding/splash_sound.dart';

/// The 8-color Minecraft palette (exact hex from the approved preview).
abstract final class MinecraftColors {
  /// Grass Green — primary.
  static const Color grassGreen = Color(0xFF58CC02);

  /// Deep Leaves — headers.
  static const Color deepLeaves = Color(0xFF2F7A12);

  /// Dirt Brown — blocks.
  static const Color dirtBrown = Color(0xFF9C6B30);

  /// Gold / XP — rewards.
  static const Color gold = Color(0xFFFFC800);

  /// Emerald — points.
  static const Color emerald = Color(0xFF00D68F);

  /// Sky Blue — info.
  static const Color skyBlue = Color(0xFF1CB0F6);

  /// Heart Red — alerts.
  static const Color heartRed = Color(0xFFFF4B4B);

  /// Cloud Sky — background.
  static const Color cloudSky = Color(0xFF8ED6FF);

  // Supporting shades (exact hex from the approved preview).
  static const Color grassBright = Color(0xFF7ED321);
  static const Color grassMid = Color(0xFF46A302);
  static const Color grassDeep = Color(0xFF1E5B0A);
  static const Color dirtDark = Color(0xFF795548);
  static const Color goldDark = Color(0xFFE5A100);
  static const Color purple = Color(0xFFCE82FF);
  static const Color stone = Color(0xFFAFAFAF);
  static const Color ink = Color(0xFF1A2E12);
  static const Color cream = Color(0xFFFFF8E1);
  static const Color paper = Color(0xFFFFFEF7);

  /// Border color for cards, panels, buttons, and quests.
  static const Color border = ink;

  /// Dark-mode surfaces (kept from the preview's dark emerald UI so
  /// dark mode stays readable; the Minecraft palette drives the
  /// primary, accents, and borders there too).
  static const Color darkBackground = Color(0xFF0C1410);
  static const Color darkCard = Color(0xFF202B25);
  static const Color darkElevated = Color(0xFF252B2D);
  static const Color darkSubtext = Color(0xFFB0B8B5);
  static const Color darkBorder = Color(0xFF343B3D);
  static const Color darkAccent = Color(0xFF34D399);
}

/// Typography families for the Minecraft theme.
abstract final class MinecraftFonts {
  /// Baloo 2 — headings, buttons, tabs, quest titles, chips/labels.
  static const String heading = 'Baloo 2';

  /// Nunito — body text.
  static const String body = 'Nunito';

  /// Press Start 2P — ONLY tiny pixel accents (logo 'E', small labels).
  static const String pixel = 'Press Start 2P';
}

/// Blocky geometry + hard shadows for the Minecraft theme.
abstract final class MinecraftShapes {
  /// Card border: 3px solid ink.
  static const double cardBorderWidth = 3;

  /// Small icon-chip border.
  static const double chipBorderWidth = 2.5;

  /// FAB border.
  static const double fabBorderWidth = 3.5;

  /// Button border.
  static const double buttonBorderWidth = 3;

  /// Card corner radius.
  static const double cardRadius = 14;

  /// Button corner radius.
  static const double buttonRadius = 12;

  /// Panel corner radius.
  static const double panelRadius = 16;

  /// Tab corner radius.
  static const double tabRadius = 11;

  /// Hard drop shadow for buttons/panels.
  static const BoxShadow hardShadow = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.22),
    offset: Offset(0, 5),
    blurRadius: 0,
  );

  /// Hard card shadow (ink, 4px drop).
  static const BoxShadow cardShadow = BoxShadow(
    color: Color.fromRGBO(26, 46, 18, 0.9),
    offset: Offset(0, 4),
    blurRadius: 0,
  );

  /// Pressed-state shadow: the hard shadow collapses to a 1px drop
  /// while the button translates down 4px ([MinecraftBlockButton]).
  static const BoxShadow pressedShadow = BoxShadow(
    color: Color.fromRGBO(0, 0, 0, 0.22),
    offset: Offset(0, 1),
    blurRadius: 0,
  );

  /// How far a block button travels down when pressed.
  static const double pressOffset = 4;

  /// Standard blocky border for cards, panels, and quests.
  static Border get blockBorder =>
      Border.all(color: MinecraftColors.border, width: cardBorderWidth);

  /// Blocky border for small icon chips.
  static Border get chipBorder =>
      Border.all(color: MinecraftColors.border, width: chipBorderWidth);

  /// Blocky border for buttons.
  static Border get buttonBorder =>
      Border.all(color: MinecraftColors.border, width: buttonBorderWidth);

  /// Blocky border for the FAB.
  static Border get fabBorder =>
      Border.all(color: MinecraftColors.border, width: fabBorderWidth);

  /// Card shape: 14px corners + 3px ink border.
  static RoundedRectangleBorder get cardShape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(cardRadius),
    side: const BorderSide(
      color: MinecraftColors.border,
      width: cardBorderWidth,
    ),
  );

  /// Button shape: 12px corners + 3px ink border.
  static RoundedRectangleBorder get buttonShape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(buttonRadius),
    side: const BorderSide(
      color: MinecraftColors.border,
      width: buttonBorderWidth,
    ),
  );

  /// Panel shape: 16px corners + 3px ink border.
  static RoundedRectangleBorder get panelShape => RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(panelRadius),
    side: const BorderSide(
      color: MinecraftColors.border,
      width: cardBorderWidth,
    ),
  );
}

/// Text styles for the Minecraft theme.
///
/// Headings use Baloo 2, body text uses Nunito at a calm 13–15px, and
/// Press Start 2P is reserved for tiny pixel accents only.
abstract final class MinecraftText {
  /// Baloo 2 heading (20sp, extra-bold). Pass [color] explicitly —
  /// styles carry size/weight only, like the rest of the app.
  static TextStyle heading({Color? color, double fontSize = 20}) =>
      GoogleFonts.baloo2(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        color: color,
      );

  /// Baloo 2 title (17sp, bold) — quest titles, card titles.
  static TextStyle title({Color? color, double fontSize = 17}) =>
      GoogleFonts.baloo2(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// Baloo 2 button / tab / chip label (15sp, bold).
  static TextStyle button({Color? color, double fontSize = 15}) =>
      GoogleFonts.baloo2(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: color,
      );

  /// Nunito body text (14sp, regular) — the calm 13–15px body size.
  static TextStyle body({Color? color, double fontSize = 14}) =>
      GoogleFonts.nunito(
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        height: 1.5,
        color: color,
      );

  /// Nunito body, semibold (14sp).
  static TextStyle bodySemiBold({Color? color, double fontSize = 14}) =>
      GoogleFonts.nunito(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        height: 1.5,
        color: color,
      );

  /// Nunito caption (13sp).
  static TextStyle caption({Color? color, double fontSize = 13}) =>
      GoogleFonts.nunito(
        fontSize: fontSize,
        fontWeight: FontWeight.w400,
        color: color,
      );

  /// Press Start 2P pixel accent (10sp) — tiny labels and the logo
  /// 'E' only. Never body text.
  static TextStyle pixel({Color? color, double fontSize = 10}) =>
      GoogleFonts.pressStart2p(fontSize: fontSize, color: color);

  /// Full text theme: Baloo 2 headings, Nunito body.
  ///
  /// Built slot-by-slot from the stock text theme: google_fonts 9's
  /// `*TextTheme` helpers return the forked `material_ui` TextTheme,
  /// which is NOT assignable to Flutter's material TextTheme, so
  /// they cannot be used here. The per-style helpers return a
  /// compatible TextStyle and are used instead.
  static TextTheme textTheme(Color bodyColor, Color headingColor) {
    final base = ThemeData.light().textTheme;
    TextStyle heading(TextStyle? slot) =>
        GoogleFonts.baloo2(textStyle: slot, color: headingColor);
    TextStyle body(TextStyle? slot) =>
        GoogleFonts.nunito(textStyle: slot, color: bodyColor);
    return base
        .copyWith(
          displayLarge: heading(base.displayLarge),
          displayMedium: heading(base.displayMedium),
          displaySmall: heading(base.displaySmall),
          headlineLarge: heading(base.headlineLarge),
          headlineMedium: heading(base.headlineMedium),
          headlineSmall: heading(base.headlineSmall),
          titleLarge: heading(base.titleLarge),
          titleMedium: heading(base.titleMedium),
          titleSmall: heading(base.titleSmall),
          bodyLarge: body(base.bodyLarge),
          bodyMedium: body(base.bodyMedium),
          bodySmall: body(base.bodySmall),
          labelLarge: body(base.labelLarge),
          labelMedium: body(base.labelMedium),
          labelSmall: body(base.labelSmall),
        )
        .apply(bodyColor: bodyColor, displayColor: headingColor);
  }
}

/// Grass / dirt / sky decorations for the Minecraft theme.
///
/// Use sparingly — page backgrounds stay readable first; the motifs
/// dress headers, logo blocks, and XP bars, not every surface.
abstract final class MinecraftDecorations {
  /// App header: grass-bright → grass-mid gradient with a 4px
  /// grass-deep bottom border.
  static BoxDecoration get grassHeader => const BoxDecoration(
    gradient: LinearGradient(
      colors: [MinecraftColors.grassBright, MinecraftColors.grassMid],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    border: Border(
      bottom: BorderSide(color: MinecraftColors.grassDeep, width: 4),
    ),
  );

  /// Logo block: white with a dirt bottom strip.
  static BoxDecoration get logoBlock => const BoxDecoration(
    color: Colors.white,
    border: Border(
      bottom: BorderSide(color: MinecraftColors.dirtBrown, width: 6),
    ),
  );

  /// Dirt strip (e.g. under a grass header or logo block).
  static BoxDecoration dirtStrip({double height = 6}) => BoxDecoration(
    color: MinecraftColors.dirtBrown,
    border: Border(
      bottom: BorderSide(color: MinecraftColors.dirtDark, width: 2),
    ),
  );

  /// Page background: sky-to-grass gradient. Pair with pixel clouds
  /// sparingly and keep content on white blocky cards for readability.
  static BoxDecoration get pageBackground => const BoxDecoration(
    gradient: LinearGradient(
      colors: [MinecraftColors.cloudSky, MinecraftColors.cream],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
  );

  /// XP bar fill: repeating grass stripes (approximated with a
  /// tiled linear gradient — Flutter has no repeating-gradient).
  static BoxDecoration get xpBarFill => const BoxDecoration(
    gradient: LinearGradient(
      colors: [
        MinecraftColors.grassGreen,
        MinecraftColors.grassBright,
        MinecraftColors.grassGreen,
        MinecraftColors.grassBright,
      ],
      stops: [0.0, 0.25, 0.5, 0.75],
      tileMode: TileMode.repeated,
    ),
  );

  /// XP bar track: cream fill with a 3px ink border.
  static BoxDecoration get xpBarTrack => BoxDecoration(
    color: MinecraftColors.cream,
    borderRadius: BorderRadius.circular(8),
    border: MinecraftShapes.blockBorder,
  );

  /// White blocky card: 3px ink border, 14px corners, hard shadow.
  static BoxDecoration blockCard({Color color = Colors.white}) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
    border: MinecraftShapes.blockBorder,
    boxShadow: const [MinecraftShapes.cardShadow],
  );

  /// Flat blocky card (Feature 4): the same 3px ink border and
  /// 14px corners as [blockCardFor], but NO hard shadow — the
  /// preview's flat note cards (student-discount note, approval
  /// queue card). Light: cream fill; dark: the elevated dark
  /// surface, 1px dark border.
  static BoxDecoration flatCardFor(Brightness brightness, {Color? color}) {
    final isDark = brightness == Brightness.dark;
    return BoxDecoration(
      color:
          color ??
          (isDark ? MinecraftColors.darkElevated : MinecraftColors.cream),
      borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
      border: Border.all(
        color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
        width: isDark ? 1 : MinecraftShapes.cardBorderWidth,
      ),
    );
  }

  /// Blocky card that follows the ambient brightness (Feature 2 —
  /// the Student tab is wrapped in StudentHubTheme, so the global
  /// Minecraft theme does not reach it; restyled tab cards use
  /// this explicitly). Light: white, 3px ink border, hard shadow.
  /// Dark: charcoal card, 1px dark border, no shadow — the same
  /// dark surface the hub already used (0xFF202B25), so the
  /// dark-mode card color is unchanged.
  static BoxDecoration blockCardFor(Brightness brightness, {Color? color}) {
    final isDark = brightness == Brightness.dark;
    return BoxDecoration(
      color: color ?? (isDark ? MinecraftColors.darkCard : Colors.white),
      borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
      border: Border.all(
        color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
        width: isDark ? 1 : MinecraftShapes.cardBorderWidth,
      ),
      boxShadow: isDark ? null : const [MinecraftShapes.cardShadow],
    );
  }

  /// Grass block button surface: grass green with a 3px ink border
  /// and the hard drop shadow. The pressed state is handled by
  /// [MinecraftBlockButton] (translateY 4px + collapsed shadow).
  static BoxDecoration blockButton({
    Color color = MinecraftColors.grassGreen,
  }) => BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(MinecraftShapes.buttonRadius),
    border: MinecraftShapes.buttonBorder,
    boxShadow: const [MinecraftShapes.hardShadow],
  );
}

/// Reusable block-button style for Material buttons.
///
/// Grass-green fill, white Baloo 2 label, 3px ink border, 12px
/// corners, min-height 40px. The press translateY effect lives in
/// [MinecraftBlockButton]; this style is for plain Material buttons
/// that only need the static blocky look.
ButtonStyle minecraftBlockButtonStyle({Color? backgroundColor}) {
  final bg = backgroundColor ?? MinecraftColors.grassGreen;
  return ButtonStyle(
    backgroundColor: WidgetStatePropertyAll(bg),
    foregroundColor: const WidgetStatePropertyAll(Colors.white),
    minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
    shape: WidgetStatePropertyAll(MinecraftShapes.buttonShape),
    textStyle: WidgetStatePropertyAll(
      MinecraftText.button(color: Colors.white),
    ),
    elevation: const WidgetStatePropertyAll(0),
  );
}

/// Reusable block-outlined style for Material buttons (Feature 2).
///
/// Transparent fill, deep-leaves Baloo 2 label, 3px ink border,
/// 12px corners, min-height 40px — the outlined partner of
/// [minecraftBlockButtonStyle].
ButtonStyle minecraftOutlinedButtonStyle() {
  return ButtonStyle(
    foregroundColor: const WidgetStatePropertyAll(MinecraftColors.deepLeaves),
    minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    ),
    side: const WidgetStatePropertyAll(
      BorderSide(
        color: MinecraftColors.border,
        width: MinecraftShapes.buttonBorderWidth,
      ),
    ),
    shape: WidgetStatePropertyAll(MinecraftShapes.buttonShape),
    textStyle: WidgetStatePropertyAll(
      MinecraftText.button(color: MinecraftColors.deepLeaves),
    ),
    elevation: const WidgetStatePropertyAll(0),
  );
}

/// A blocky Minecraft button with the press effect: on press it
/// translates down 4px and its hard shadow collapses to 1px.
class MinecraftBlockButton extends StatefulWidget {
  const MinecraftBlockButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.backgroundColor = MinecraftColors.grassGreen,
    this.icon,
    this.sound = MinecraftSoundKind.click,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final IconData? icon;

  /// Tap sound (Feature 6): click by default; callers pass the
  /// kind their action maps to (e.g. levelup for Save,
  /// forge for 'Forge a Quiz').
  final MinecraftSoundKind sound;

  @override
  State<MinecraftBlockButton> createState() => _MinecraftBlockButtonState();
}

class _MinecraftBlockButtonState extends State<MinecraftBlockButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    // Feature 5: the tap squash composes with the button's own
    // press translate (4px down + collapsed shadow) — different
    // transform, same tap. The wrapper only observes the pointer
    // here; the GestureDetector below still owns the tap.
    return GestureDetector(
      onTap: widget.onPressed,
      onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
      onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
      child: MinecraftTapAnimation(
        enabled: enabled,
        sound: widget.sound,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          transform: Matrix4.translationValues(
            0,
            _pressed ? MinecraftShapes.pressOffset : 0,
            0,
          ),
          decoration: BoxDecoration(
            color: enabled ? widget.backgroundColor : MinecraftColors.stone,
            borderRadius: BorderRadius.circular(MinecraftShapes.buttonRadius),
            border: MinecraftShapes.buttonBorder,
            boxShadow: [
              _pressed
                  ? MinecraftShapes.pressedShadow
                  : MinecraftShapes.hardShadow,
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: Colors.white, size: 18),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: MinecraftText.button(color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A Minecraft quest card: white, 3px ink border, hard shadow, a
/// 46px letter-block badge (Baloo 2), title + details, and the XP
/// reward on the right.
///
/// Feature 3 (Classes quest board): [xp] is optional — classes
/// carry no per-class XP in the app, so a quest row shows no XP
/// chip rather than an invented number. Pass [chip] for a real
/// status chip instead (e.g. 'Next up' / 'New'), and [trailing]
/// for row actions (e.g. the class edit/delete buttons). [badgeIcon]
/// swaps the letter badge for an icon badge (e.g. the flashcard
/// chest box / box-open).
class MinecraftQuestCard extends StatelessWidget {
  const MinecraftQuestCard({
    super.key,
    this.badgeLetter,
    this.badgeIcon,
    required this.title,
    required this.details,
    this.xp,
    this.chip,
    this.trailing,
    this.badgeColor = MinecraftColors.grassGreen,
    this.badgeIconColor = Colors.white,
    this.onTap,
    this.sound = MinecraftSoundKind.pop,
  }) : assert(
         badgeLetter != null || badgeIcon != null,
         'MinecraftQuestCard needs a badge letter or a badge icon',
       );

  /// Single letter shown in the block badge (e.g. 'Q'). Use
  /// [badgeIcon] instead for an icon badge.
  final String? badgeLetter;

  /// Icon shown in the block badge instead of [badgeLetter].
  final IconData? badgeIcon;

  /// Icon color for [badgeIcon] (gold badges use a dark icon).
  final Color badgeIconColor;

  /// Quest title (Baloo 2).
  final String title;

  /// Quest details (Nunito body).
  final String details;

  /// XP reward amount, shown as e.g. '50 XP' on the right. Null =
  /// no XP chip (the app has no per-class XP — never invent one).
  final int? xp;

  /// A real status chip shown in place of the XP chip (e.g. 'Next
  /// up' / 'New'). Takes precedence over [xp].
  final Widget? chip;

  /// Row actions rendered after the chip (e.g. edit / delete).
  final Widget? trailing;

  /// Badge fill color.
  final Color badgeColor;

  final VoidCallback? onTap;

  /// Tap sound (Feature 6): quest rows play pop by default.
  final MinecraftSoundKind sound;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : MinecraftColors.ink;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
        // Feature 5: tap squash + ring/bits. The wrapper only
        // observes the pointer; the InkWell still owns the tap.
        // Feature 6: quest rows play [sound] (pop by default).
        child: MinecraftTapAnimation(
          enabled: onTap != null,
          sound: sound,
          child: Container(
            decoration: MinecraftDecorations.blockCardFor(
              Theme.of(context).brightness,
            ),
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  key: const Key('quest-badge'),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? MinecraftColors.darkBorder
                          : MinecraftColors.border,
                      width: MinecraftShapes.cardBorderWidth,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: badgeIcon != null
                      ? Icon(badgeIcon, color: badgeIconColor, size: 24)
                      : Text(
                          badgeLetter!,
                          style: MinecraftText.heading(
                            color: Colors.white,
                            fontSize: 22,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: MinecraftText.title(color: onSurface)),
                      const SizedBox(height: 2),
                      Text(
                        details,
                        style: MinecraftText.body(color: onSurface),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (chip != null)
                  chip!
                else if (xp != null)
                  Container(
                    key: const Key('quest-xp'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: MinecraftColors.gold,
                      borderRadius: BorderRadius.circular(8),
                      border: MinecraftShapes.chipBorder,
                    ),
                    child: Text(
                      '$xp XP',
                      style: MinecraftText.button(
                        color: MinecraftColors.ink,
                        fontSize: 13,
                      ),
                    ),
                  ),
                if (trailing != null) ...[const SizedBox(width: 4), trailing!],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A blocky gold XP-style status chip (Feature 3): gold fill, 2.5px
/// ink border, Baloo 2 label — the preview's quest-chip treatment,
/// carrying a REAL status ('Next up', 'New', '75%') instead of an
/// invented XP number.
class MinecraftStatusChip extends StatelessWidget {
  const MinecraftStatusChip(
    this.label, {
    super.key,
    this.backgroundColor = MinecraftColors.gold,
    this.textColor = MinecraftColors.ink,
  });

  final String label;
  final Color backgroundColor;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: MinecraftShapes.chipBorder,
      ),
      child: Text(
        label,
        style: MinecraftText.button(color: textColor, fontSize: 13),
      ),
    );
  }
}

/// A blocky 58px square FAB (Feature 3): grass green, 3.5px ink
/// border, hard shadow, 16px corners. The caller owns the child
/// (usually a + icon with its own rotate/scale animation) and the
/// tap handler.
class MinecraftFabButton extends StatelessWidget {
  const MinecraftFabButton({
    super.key,
    required this.child,
    required this.onPressed,
    this.tooltip,
    this.size = 58,
    this.sound = MinecraftSoundKind.pop,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;

  /// Tap sound (Feature 6): the FAB (+) plays pop by default.
  final MinecraftSoundKind sound;

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          // Feature 5: tap squash + ring/bits. The wrapper only
          // observes the pointer; the InkWell still owns the tap.
          // Feature 6: the FAB plays [sound] (pop by default).
          child: MinecraftTapAnimation(
            enabled: onPressed != null,
            sound: sound,
            child: Container(
              decoration: BoxDecoration(
                color: MinecraftColors.grassGreen,
                borderRadius: BorderRadius.circular(16),
                border: MinecraftShapes.fabBorder,
                boxShadow: const [MinecraftShapes.hardShadow],
              ),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}

/// A blocky section header (Feature 3): a grass icon badge + a
/// Baloo 2 title, with an optional trailing widget (e.g. a link).
class MinecraftSectionHeader extends StatelessWidget {
  const MinecraftSectionHeader({
    super.key,
    required this.icon,
    required this.title,
    this.iconColor = MinecraftColors.grassGreen,
    this.trailing = const SizedBox.shrink(),
  });

  final IconData icon;
  final String title;
  final Color iconColor;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        MinecraftIconBadge(
          icon: icon,
          backgroundColor: iconColor,
          size: 36,
          iconSize: 20,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: MinecraftText.heading(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 17,
            ),
          ),
        ),
        trailing,
      ],
    );
  }
}

/// A Minecraft blocky card (Feature 2 — Student tab restyle).
///
/// Dark-aware surface + border via [MinecraftDecorations.blockCardFor]
/// (white / 3px ink border / hard shadow in light; charcoal / 1px
/// dark border in dark). [onTap] wraps the content in an InkWell
/// clipped to the card shape; without it the card is static. The
/// [Material] carries the surface color so the card reads correctly
/// under themes that report their card color (the Student hub's
/// dark-mode test reads it).
class MinecraftCard extends StatelessWidget {
  const MinecraftCard({
    super.key,
    required this.child,
    this.onTap,
    this.color,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final surface = color ?? (isDark ? MinecraftColors.darkCard : Colors.white);
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
      side: BorderSide(
        color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
        width: isDark ? 1 : MinecraftShapes.cardBorderWidth,
      ),
    );
    final content = Padding(padding: padding, child: child);
    return Container(
      decoration: MinecraftDecorations.blockCardFor(brightness, color: color),
      child: Material(
        color: surface,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

/// A square block badge for card headers (Feature 2): a colored
/// block with a 2.5px border and a centered icon — the quest-badge
/// motif from the approved preview, sized for headers.
class MinecraftIconBadge extends StatelessWidget {
  const MinecraftIconBadge({
    super.key,
    required this.icon,
    this.backgroundColor = MinecraftColors.grassGreen,
    this.iconColor = Colors.white,
    this.size = 40,
    this.iconSize = 22,
  });

  final IconData icon;
  final Color backgroundColor;
  final Color iconColor;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? MinecraftColors.darkBorder : MinecraftColors.border,
          width: MinecraftShapes.chipBorderWidth,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: iconColor, size: iconSize),
    );
  }
}

/// A Minecraft XP bar (Feature 2): cream track with a 3px ink
/// border, grass-stripe fill ([MinecraftDecorations.xpBarFill]).
/// [animate] (default true) eases 0 -> [value] over 600 ms like
/// the sign-in bar it replaces; pass false when the caller already
/// animates the value (e.g. the Student tab entrance driving the
/// Walking Goal fill frame by frame).
class MinecraftXpBar extends StatelessWidget {
  const MinecraftXpBar({
    super.key,
    required this.value,
    this.height = 14,
    this.animate = true,
  });

  /// Fill fraction, 0..1.
  final double value;

  final double height;

  final bool animate;

  @override
  Widget build(BuildContext context) {
    if (!animate) return _bar(value.clamp(0.0, 1.0));
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOut,
      builder: (context, animated, _) => _bar(animated),
    );
  }

  Widget _bar(double fraction) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 3px track border on each side: the fill lives inside it.
        final innerWidth = constraints.maxWidth - 6;
        final fillWidth = (innerWidth * fraction).clamp(0.0, innerWidth);
        return Container(
          height: height,
          decoration: MinecraftDecorations.xpBarTrack,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: fillWidth,
              height: height - 6,
              margin: const EdgeInsets.only(left: 3),
              decoration: MinecraftDecorations.xpBarFill.copyWith(
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The global MaterialApp theme for a brightness, in Minecraft tokens.
///
/// Light: paper background, white blocky cards with 3px ink borders
/// and hard shadows, grass-green primary, Baloo 2 headings, Nunito
/// body. Dark: the preview's dark emerald surfaces for readability,
/// with the same grass-green primary, gold XP, and Baloo 2 / Nunito
/// typography. The dark emerald brand green is present in both (the
/// Minecraft palette IS green: grass #58CC02 over deep leaves).
ThemeData minecraftThemeData(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scaffoldBackground = isDark
      ? MinecraftColors.darkBackground
      : MinecraftColors.paper;
  final cardColor = isDark ? MinecraftColors.darkCard : Colors.white;
  final onSurface = isDark ? Colors.white : MinecraftColors.ink;
  final onSurfaceVariant = isDark
      ? MinecraftColors.darkSubtext
      : const Color(0xFF5B6B52);
  final borderColor = isDark
      ? MinecraftColors.darkBorder
      : MinecraftColors.border;
  final borderSide = BorderSide(color: borderColor, width: isDark ? 1 : 3);
  final scheme = isDark
      ? const ColorScheme.dark(
          primary: MinecraftColors.grassGreen,
          onPrimary: Colors.white,
          secondary: MinecraftColors.darkAccent,
          onSecondary: Color(0xFF052E16),
          tertiary: MinecraftColors.gold,
          surface: MinecraftColors.darkCard,
          onSurface: Colors.white,
          surfaceContainerHighest: MinecraftColors.darkElevated,
          onSurfaceVariant: MinecraftColors.darkSubtext,
          outline: MinecraftColors.darkBorder,
          error: MinecraftColors.heartRed,
        )
      : const ColorScheme.light(
          primary: MinecraftColors.grassGreen,
          onPrimary: Colors.white,
          secondary: MinecraftColors.deepLeaves,
          tertiary: MinecraftColors.gold,
          surface: Colors.white,
          onSurface: MinecraftColors.ink,
          surfaceContainerHighest: MinecraftColors.cream,
          onSurfaceVariant: Color(0xFF5B6B52),
          outline: MinecraftColors.border,
          error: MinecraftColors.heartRed,
        );
  final textTheme = MinecraftText.textTheme(onSurfaceVariant, onSurface);
  final cardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(MinecraftShapes.cardRadius),
    side: borderSide,
  );
  final buttonShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(MinecraftShapes.buttonRadius),
    side: borderSide,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: scaffoldBackground,
    appBarTheme: AppBarTheme(
      backgroundColor: isDark ? MinecraftColors.darkBackground : Colors.white,
      foregroundColor: onSurface,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: MinecraftText.heading(color: onSurface, fontSize: 20),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? MinecraftColors.darkBackground : Colors.white,
      elevation: 0,
      indicatorColor: isDark
          ? const Color(0xFF064E3B)
          : const Color(0xFFD9F7C4),
      iconTheme: const WidgetStatePropertyAll(IconThemeData(size: 24)),
      labelTextStyle: WidgetStatePropertyAll(
        MinecraftText.button(fontSize: 12),
      ),
    ),
    cardTheme: CardThemeData(
      color: cardColor,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: cardShape,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MinecraftShapes.panelRadius),
        side: borderSide,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: cardColor,
      modalBackgroundColor: cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(MinecraftShapes.panelRadius),
        ),
        side: borderSide,
      ),
      showDragHandle: true,
      dragHandleColor: borderColor,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: isDark
          ? MinecraftColors.darkElevated
          : MinecraftColors.cream,
      selectedColor: MinecraftColors.grassGreen,
      labelStyle: MinecraftText.button(color: onSurface, fontSize: 13),
      secondaryLabelStyle: MinecraftText.button(
        color: Colors.white,
        fontSize: 13,
      ),
      side: borderSide,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(MinecraftShapes.tabRadius),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? MinecraftColors.darkElevated : MinecraftColors.paper,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MinecraftShapes.buttonRadius),
        borderSide: borderSide,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MinecraftShapes.buttonRadius),
        borderSide: borderSide,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(MinecraftShapes.buttonRadius),
        borderSide: const BorderSide(
          color: MinecraftColors.grassGreen,
          width: 3,
        ),
      ),
      hintStyle: MinecraftText.body(color: onSurfaceVariant),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: MinecraftColors.grassGreen,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 40),
        shape: buttonShape,
        textStyle: MinecraftText.button(color: Colors.white),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: MinecraftColors.grassGreen,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 40),
        shape: buttonShape,
        textStyle: MinecraftText.button(color: Colors.white),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: MinecraftColors.deepLeaves,
        minimumSize: const Size(0, 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MinecraftShapes.buttonRadius),
        ),
        textStyle: MinecraftText.button(color: MinecraftColors.deepLeaves),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: MinecraftColors.deepLeaves,
        minimumSize: const Size(0, 40),
        side: const BorderSide(
          color: MinecraftColors.border,
          width: MinecraftShapes.buttonBorderWidth,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MinecraftShapes.buttonRadius),
        ),
        textStyle: MinecraftText.button(color: MinecraftColors.deepLeaves),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: MinecraftColors.grassGreen,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        side: BorderSide(
          color: MinecraftColors.border,
          width: MinecraftShapes.fabBorderWidth,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineWidth: const WidgetStatePropertyAll(0),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? MinecraftColors.grassGreen
            : borderColor,
      ),
    ),
    dividerTheme: DividerThemeData(color: borderColor, thickness: 1),
  );
}
