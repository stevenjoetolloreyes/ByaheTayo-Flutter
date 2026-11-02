// Shared layout system for the ENTIRE EstudyanteGO app.
//
// ONE source of truth for page margins, card geometry, gaps, corner
// radii, and the typography scale. Screens reference these tokens
// instead of scattering inline literals — so a margin or size is
// changed in exactly one place, and light + dark stay identical
// (only colors/surfaces/borders change with brightness; every
// measurement below is brightness-independent).
//
// MEASUREMENT RULES (do not break these):
// - Tab content pages use 16dp side margins. Full screens (entry
//   screens, Rewards, the student ID page) and bottom sheets use
//   24dp. Two page paddings by surface type — each surface uses
//   its token consistently. Never a third page margin.
// - Cards: 16dp padding, 12dp gaps between cards, 16dp corners.
//   Card margin stays the Card default (4dp) — zeroing it would
//   shift every card 4dp outward, and the friends tests pin
//   content at margin 4 + padding 16.
// - Content is single-column, full available width, on EVERY size
//   (phones, tablets, portrait, landscape). No narrow centered
//   container: the shell's sidebar (tablets) or bottom nav
//   (phones) is the only width constraint. Do not add max widths.
// - Entry screens keep their approved measurements: 24dp page
//   margins, 18dp card corners, 14dp input corners, 52dp buttons,
//   26sp/1.2 titles, 16sp/1.5 descriptions. Those values are
//   tokens here — never changed by the tab system.
// - Friends tab alignment (approved fix, do not regress):
//   headings/descriptions LEFT; empty-state illustration/title/
//   note CENTERED; QR + code CENTERED; Copy + Share in one row
//   when card content width is >= 280dp, stacked below that.
// - The sidebar and six-tab navigation are never moved by this
//   file; the shell in lib/main.dart owns them.
//
// Typography: the scale below names every body-text size the app
// uses. Styles carry size/weight/height ONLY — color always comes
// from the call site (Theme colorScheme), so one style works in
// light and dark. One-off display artwork (splash logo sizes,
// huge points numerals) is not body text and stays out of the
// scale on purpose.
import 'package:flutter/material.dart';

/// Spacing scale (dp). Every gap/padding in the app maps to one of
/// these values; do not invent ad-hoc numbers.
abstract final class AppSpacing {
  static const double s2 = 2;
  static const double s4 = 4;
  static const double s8 = 8;
  static const double s12 = 12;
  static const double s16 = 16;
  static const double s20 = 20;
  static const double s24 = 24;
}

/// Page, card, and component geometry.
abstract final class AppLayout {
  /// Tab content pages (all six tabs + student module pages).
  static const EdgeInsets pagePaddingTab = EdgeInsets.all(16);

  /// Full screens (entry screens, Rewards, student ID page) and
  /// bottom sheets.
  static const EdgeInsets pagePaddingLarge = EdgeInsets.all(24);

  /// Standard card inner padding.
  static const EdgeInsets cardPadding = EdgeInsets.all(16);

  /// Gap between cards in a tab list.
  static const double cardGap = 12;

  /// Gap after a page header / search field / before a footer note
  /// (the 16dp rhythm that opens and closes a tab page).
  static const double headerGap = 16;

  /// Card corner radius — matches the global cardTheme in main.dart
  /// (light + dark) and the student theme. Card margin stays the
  /// Card default (4dp); never set it to zero.
  static const double cardRadius = 16;

  /// Entry-screen card corners (approved entry spec: range 16-20).
  static const double cardRadiusEntry = 18;

  /// Tab input corners (friends search + code entry fields).
  static const double inputRadiusTab = 12;

  /// Entry input corners (approved entry spec: range 12-16).
  static const double inputRadiusEntry = 14;

  /// Small info-note container corners (friends sync note).
  static const double noteRadius = 12;

  /// Friends empty-state illustration container.
  static const double emptyIllustrationRadius = 20;
  static const double emptyIllustrationSize = 72;

  /// Friends QR code size.
  static const double qrSize = 180;

  /// Friends Copy/Share row breakpoint: one row at or above this
  /// card content width, stacked below it.
  static const double codeActionRowMinWidth = 280;

  /// Navigation icon size (shell NavigationBar + sidebar).
  static const double navIconSize = 24;

  /// Entry button corner radius (approved entry spec: range 14-18).
  static const double buttonRadius = 16;

  /// Entry dialog corner radius.
  static const double dialogRadius = 20;
}

/// ONE typography scale. Sizes/weights/heights only — never colors.
abstract final class AppText {
  static const TextStyle displayLarge =
      TextStyle(fontSize: 32, fontWeight: FontWeight.w800);
  static const TextStyle displayMedium =
      TextStyle(fontSize: 28, fontWeight: FontWeight.w800);

  /// Onboarding titles (approved: 26sp w800 / 1.2).
  static const TextStyle titleLarge =
      TextStyle(fontSize: 26, fontWeight: FontWeight.w800, height: 1.2);

  /// Tab page titles ('Friends', 'Know your fare before you go').
  static const TextStyle pageTitle =
      TextStyle(fontSize: 22, fontWeight: FontWeight.w800);

  /// 24sp strong titles (verify-email heading).
  static const TextStyle titleMedium =
      TextStyle(fontSize: 24, fontWeight: FontWeight.w800);

  /// AppBar titles + account header titles.
  static const TextStyle titleSmall =
      TextStyle(fontSize: 20, fontWeight: FontWeight.w700);

  /// Strong 20sp titles (student greeting banner, sheet titles).
  static const TextStyle titleStrong =
      TextStyle(fontSize: 20, fontWeight: FontWeight.w800);

  static const TextStyle heading =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w700);
  static const TextStyle headingStrong =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w800);

  /// Section titles inside cards ('My Friends', 'Student Hub').
  static const TextStyle sectionTitle =
      TextStyle(fontSize: 17, fontWeight: FontWeight.w700);
  static const TextStyle bodyLarge = TextStyle(fontSize: 17);

  static const TextStyle body = TextStyle(fontSize: 16);

  /// Onboarding descriptions (approved: 16sp / 1.5).
  static const TextStyle bodyRelaxed =
      TextStyle(fontSize: 16, height: 1.5);
  static const TextStyle bodySmall = TextStyle(fontSize: 15);

  /// Subsection labels ('Incoming', 'Outgoing').
  static const TextStyle labelStrong =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w700);
  static const TextStyle label = TextStyle(fontSize: 14);
  static const TextStyle caption = TextStyle(fontSize: 13);

  /// Colored status labels (request status lines).
  static const TextStyle captionStrong =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w700);

  /// Small semibold labels (quick-access item labels).
  static const TextStyle captionSemiBold =
      TextStyle(fontSize: 13, fontWeight: FontWeight.w600);

  /// Badge labels (Day badge, reference chips).
  static const TextStyle smallBold =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w700);

  /// Strong body values (stat values).
  static const TextStyle bodyStrong =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w800);

  /// Large numerals without a line-height (balance amounts).
  static const TextStyle displaySmall =
      TextStyle(fontSize: 26, fontWeight: FontWeight.w800);

  /// Person names in friend/request rows.
  static const TextStyle name =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
  static const TextStyle small = TextStyle(fontSize: 12);

  /// NavigationBar labels.
  static const TextStyle smallSemiBold =
      TextStyle(fontSize: 12, fontWeight: FontWeight.w600);
  static const TextStyle tiny = TextStyle(fontSize: 11);
  static const TextStyle micro = TextStyle(fontSize: 10);

  /// Entry buttons (approved: 16sp semibold, 52dp tall).
  static const TextStyle button =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w600);
  static const TextStyle buttonSmall =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w600);

  /// Card titles ('Know something that can help commuters?').
  static const TextStyle cardTitle =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700);

  /// Empty-state titles (friends).
  static const TextStyle emptyTitle =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
}

/// Card with the shared tab geometry: theme 16dp corners + 16dp
/// padding. Replaces `Card(child: Padding(all(16), ...))` patterns
/// without changing any measurement. The Card margin is left at
/// its default (4dp) on purpose — see [AppLayout] above.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: AppLayout.cardPadding,
        child: child,
      ),
    );
  }
}
