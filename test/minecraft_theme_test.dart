// Minecraft theme foundation tests (Feature 1): palette hex values,
// blocky geometry, typography families, button / quest-card styles,
// and the global light + dark ThemeData built from the tokens.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:estudyantego/features/minecraft_theme.dart';

void main() {
  group('MinecraftColors palette (approved preview hex)', () {
    test('8-color palette', () {
      expect(MinecraftColors.grassGreen, const Color(0xFF58CC02));
      expect(MinecraftColors.deepLeaves, const Color(0xFF2F7A12));
      expect(MinecraftColors.dirtBrown, const Color(0xFF9C6B30));
      expect(MinecraftColors.gold, const Color(0xFFFFC800));
      expect(MinecraftColors.emerald, const Color(0xFF00D68F));
      expect(MinecraftColors.skyBlue, const Color(0xFF1CB0F6));
      expect(MinecraftColors.heartRed, const Color(0xFFFF4B4B));
      expect(MinecraftColors.cloudSky, const Color(0xFF8ED6FF));
    });

    test('supporting shades', () {
      expect(MinecraftColors.grassBright, const Color(0xFF7ED321));
      expect(MinecraftColors.grassMid, const Color(0xFF46A302));
      expect(MinecraftColors.grassDeep, const Color(0xFF1E5B0A));
      expect(MinecraftColors.dirtDark, const Color(0xFF795548));
      expect(MinecraftColors.goldDark, const Color(0xFFE5A100));
      expect(MinecraftColors.purple, const Color(0xFFCE82FF));
      expect(MinecraftColors.stone, const Color(0xFFAFAFAF));
      expect(MinecraftColors.ink, const Color(0xFF1A2E12));
      expect(MinecraftColors.cream, const Color(0xFFFFF8E1));
      expect(MinecraftColors.paper, const Color(0xFFFFFEF7));
    });

    test('border color is ink', () {
      expect(MinecraftColors.border, MinecraftColors.ink);
    });
  });

  group('MinecraftShapes blocky geometry', () {
    test('border widths: cards 3, chips 2.5, FAB 3.5, buttons 3', () {
      expect(MinecraftShapes.cardBorderWidth, 3);
      expect(MinecraftShapes.chipBorderWidth, 2.5);
      expect(MinecraftShapes.fabBorderWidth, 3.5);
      expect(MinecraftShapes.buttonBorderWidth, 3);
    });

    test('radii: cards 14, buttons 12, panels 16, tabs 11', () {
      expect(MinecraftShapes.cardRadius, 14);
      expect(MinecraftShapes.buttonRadius, 12);
      expect(MinecraftShapes.panelRadius, 16);
      expect(MinecraftShapes.tabRadius, 11);
    });

    test('hard shadows drop straight down with no blur', () {
      expect(MinecraftShapes.hardShadow.offset, const Offset(0, 5));
      expect(MinecraftShapes.hardShadow.blurRadius, 0);
      expect(MinecraftShapes.cardShadow.offset, const Offset(0, 4));
      expect(MinecraftShapes.cardShadow.blurRadius, 0);
      expect(MinecraftShapes.pressedShadow.offset, const Offset(0, 1));
      expect(MinecraftShapes.pressOffset, 4);
    });

    test('card shape: 14px corners + 3px ink border', () {
      final shape = MinecraftShapes.cardShape;
      expect(shape.borderRadius,
          BorderRadius.circular(MinecraftShapes.cardRadius));
      expect(shape.side.color, MinecraftColors.ink);
      expect(shape.side.width, 3);
    });
  });

  group('MinecraftText typography', () {
    test('headings Baloo 2, body Nunito, pixel accents Press Start 2P', () {
      // google_fonts registers the downloaded font under a
      // weight-suffixed family name (e.g. 'Baloo2_800',
      // 'Nunito_regular'), so assert the family prefix, not the
      // display name.
      expect(MinecraftText.heading().fontFamily, startsWith('Baloo2'));
      expect(MinecraftText.title().fontFamily, startsWith('Baloo2'));
      expect(MinecraftText.button().fontFamily, startsWith('Baloo2'));
      expect(MinecraftText.body().fontFamily, startsWith('Nunito'));
      expect(MinecraftText.body().fontSize, 14);
      expect(MinecraftText.pixel().fontFamily, startsWith('PressStart2P'));
    });
  });

  group('MinecraftDecorations motifs', () {
    test('grass header: bright-to-mid gradient, 4px deep bottom border', () {
      final decoration = MinecraftDecorations.grassHeader;
      final gradient = decoration.gradient as LinearGradient;
      expect(gradient.colors, [
        MinecraftColors.grassBright,
        MinecraftColors.grassMid,
      ]);
      expect(decoration.border!.bottom.color, MinecraftColors.grassDeep);
      expect(decoration.border!.bottom.width, 4);
    });

    test('logo block: white with a dirt bottom strip', () {
      final decoration = MinecraftDecorations.logoBlock;
      expect(decoration.color, Colors.white);
      expect(decoration.border!.bottom.color, MinecraftColors.dirtBrown);
    });

    test('XP bar fill uses grass stripes', () {
      final decoration = MinecraftDecorations.xpBarFill;
      final gradient = decoration.gradient as LinearGradient;
      expect(gradient.colors.first, MinecraftColors.grassGreen);
      expect(gradient.tileMode, TileMode.repeated);
    });

    test('block card: white, 3px ink border, hard card shadow', () {
      final decoration = MinecraftDecorations.blockCard();
      expect(decoration.color, Colors.white);
      expect(decoration.borderRadius,
          BorderRadius.circular(MinecraftShapes.cardRadius));
      expect(decoration.boxShadow, [MinecraftShapes.cardShadow]);
    });
  });

  group('minecraftBlockButtonStyle', () {
    test('grass fill, 12px corners, 3px ink border, min height 40', () {
      final style = minecraftBlockButtonStyle();
      expect(style.backgroundColor!.resolve({}),
          MinecraftColors.grassGreen);
      expect(style.foregroundColor!.resolve({}), Colors.white);
      expect(style.minimumSize!.resolve({})?.height, 40);
      final shape =
          style.shape!.resolve({}) as RoundedRectangleBorder;
      expect(shape.borderRadius,
          BorderRadius.circular(MinecraftShapes.buttonRadius));
      expect(shape.side.color, MinecraftColors.ink);
      expect(shape.side.width, 3);
    });
  });

  group('minecraftThemeData', () {
    test('light: grass primary, paper scaffold, blocky cards', () {
      final theme = minecraftThemeData(Brightness.light);
      expect(theme.colorScheme.primary, MinecraftColors.grassGreen);
      expect(theme.scaffoldBackgroundColor, MinecraftColors.paper);
      expect(theme.textTheme.bodyMedium?.fontFamily, startsWith('Nunito'));
      expect(theme.textTheme.titleLarge?.fontFamily, startsWith('Baloo2'));
      final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
      expect(cardShape.borderRadius,
          BorderRadius.circular(MinecraftShapes.cardRadius));
      expect(cardShape.side.width, 3);
      final buttonShape = theme.filledButtonTheme.style!.shape!
          .resolve({}) as RoundedRectangleBorder;
      expect(buttonShape.borderRadius,
          BorderRadius.circular(MinecraftShapes.buttonRadius));
    });

    test('dark: same grass primary, dark surfaces, Nunito/Baloo 2', () {
      final theme = minecraftThemeData(Brightness.dark);
      expect(theme.colorScheme.primary, MinecraftColors.grassGreen);
      expect(theme.scaffoldBackgroundColor,
          MinecraftColors.darkBackground);
      expect(theme.textTheme.bodyMedium?.fontFamily, startsWith('Nunito'));
      expect(theme.textTheme.titleLarge?.fontFamily, startsWith('Baloo2'));
    });
  });

  group('MinecraftBlockButton widget', () {
    testWidgets('shows its label and fires onPressed on tap',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MinecraftBlockButton(
              label: 'Start Quest',
              onPressed: () => tapped = true,
            ),
          ),
        ),
      );
      expect(find.text('Start Quest'), findsOneWidget);
      await tester.tap(find.text('Start Quest'));
      await tester.pump();
      expect(tapped, isTrue);
    });
  });

  group('MinecraftQuestCard widget', () {
    testWidgets('badge letter, title, details, and XP reward render',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MinecraftQuestCard(
              badgeLetter: 'Q',
              title: 'Ride the bus',
              details: 'Take 3 rides this week',
              xp: 50,
            ),
          ),
        ),
      );
      expect(find.text('Q'), findsOneWidget);
      expect(find.text('Ride the bus'), findsOneWidget);
      expect(find.text('Take 3 rides this week'), findsOneWidget);
      expect(find.text('50 XP'), findsOneWidget);
      expect(find.byKey(const Key('quest-badge')), findsOneWidget);
      expect(find.byKey(const Key('quest-xp')), findsOneWidget);
    });
  });
}
