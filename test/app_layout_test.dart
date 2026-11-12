// Shared layout system tests: token values + no-overflow rendering
// of token-built pages at phone/tablet widths, portrait/landscape,
// light/dark. These pin the ONE layout system so a future edit that
// drifts a margin, radius, or type size fails here first.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:estudyantego/features/app_layout.dart';

void main() {
  group('AppLayout tokens', () {
    test('page paddings: tabs 16, full screens + sheets 24', () {
      expect(AppLayout.pagePaddingTab, const EdgeInsets.all(16));
      expect(AppLayout.pagePaddingLarge, const EdgeInsets.all(24));
    });

    test('card geometry: 16 padding, 12 gaps, 14 corners', () {
      expect(AppLayout.cardPadding, const EdgeInsets.all(16));
      expect(AppLayout.cardGap, 12);
      expect(AppLayout.cardRadius, 14);
    });

    test('header/footer rhythm is 16', () {
      expect(AppLayout.headerGap, 16);
    });

    test('entry corners preserved: cards 18, inputs 14', () {
      expect(AppLayout.cardRadiusEntry, 18);
      expect(AppLayout.inputRadiusEntry, 14);
    });

    test('tab input corners are 12', () {
      expect(AppLayout.inputRadiusTab, 12);
    });

    test('friends alignment constants preserved', () {
      expect(AppLayout.emptyIllustrationRadius, 20);
      expect(AppLayout.emptyIllustrationSize, 72);
      expect(AppLayout.qrSize, 180);
      expect(AppLayout.codeActionRowMinWidth, 280);
    });
  });

  group('AppText scale', () {
    test('approved entry typography: titles 26/1.2, descriptions 16/1.5', () {
      expect(AppText.titleLarge.fontSize, 26);
      expect(AppText.titleLarge.fontWeight, FontWeight.w800);
      expect(AppText.titleLarge.height, 1.2);
      expect(AppText.bodyRelaxed.fontSize, 16);
      expect(AppText.bodyRelaxed.height, 1.5);
    });

    test('page + section titles', () {
      expect(AppText.pageTitle.fontSize, 22);
      expect(AppText.pageTitle.fontWeight, FontWeight.w800);
      expect(AppText.sectionTitle.fontSize, 17);
      expect(AppText.sectionTitle.fontWeight, FontWeight.w700);
    });

    test('buttons + nav labels', () {
      expect(AppText.button.fontSize, 16);
      expect(AppText.button.fontWeight, FontWeight.w600);
      expect(AppText.smallSemiBold.fontSize, 12);
      expect(AppText.smallSemiBold.fontWeight, FontWeight.w600);
    });
  });

  group('AppCard', () {
    testWidgets('uses shared card padding', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: AppCard(child: Text('hello'))),
        ),
      );
      // Card's own margin renders as a 4dp Padding too, so match the inner
      // padding by value instead of taking the first Padding in the tree.
      expect(
        find.byWidgetPredicate(
          (w) => w is Padding && w.padding == AppLayout.cardPadding,
        ),
        findsOneWidget,
      );
      expect(find.text('hello'), findsOneWidget);
    });
  });

  group('Token page no-overflow', () {
    Widget tokenPage() {
      return MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: ListView(
              padding: AppLayout.pagePaddingTab,
              children: [
                Text('Page title', style: AppText.pageTitle),
                const SizedBox(height: AppLayout.headerGap),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.people_outlined),
                          SizedBox(width: AppLayout.cardGap),
                          Expanded(
                            child: Text(
                              'A section title that is long enough to wrap',
                              style: AppText.sectionTitle,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: AppLayout.cardGap),
                      Text(
                        'Body copy at the shared body size, with a '
                        'long line to exercise wrapping.',
                        style: AppText.body,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppLayout.cardGap),
                AppCard(
                  child: Text('Second card', style: AppText.cardTitle),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Future<void> expectNoOverflow(
      WidgetTester tester,
      Size size,
      ThemeData theme,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        Theme(data: theme, child: tokenPage()),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets('phone portrait light', (tester) async {
      await expectNoOverflow(
        tester,
        const Size(390, 844),
        ThemeData.light(),
      );
    });

    testWidgets('phone landscape light', (tester) async {
      await expectNoOverflow(
        tester,
        const Size(844, 390),
        ThemeData.light(),
      );
    });

    testWidgets('tablet portrait dark', (tester) async {
      await expectNoOverflow(
        tester,
        const Size(800, 1000),
        ThemeData.dark(),
      );
    });

    testWidgets('tablet landscape dark', (tester) async {
      await expectNoOverflow(
        tester,
        const Size(1000, 800),
        ThemeData.dark(),
      );
    });

    testWidgets('narrow phone 320 wide', (tester) async {
      await expectNoOverflow(
        tester,
        const Size(320, 640),
        ThemeData.light(),
      );
    });
  });
}
