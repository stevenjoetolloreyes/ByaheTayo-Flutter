// Widget tests for the Feature 4 Minecraft restyle of the Fares
// and Communities tabs (Nov 10, 2026): the approved preview's
// blocky fare cards, blocky post cards, flat student-discount note,
// and flat approval queue card — with the tabs' LIVE data, never
// the preview's sample fares or posts.
//
// What is NOT asserted here: the preview's sample fares (Vigan →
// Laoag ₱120/₱96, Cabugao → Laoag ₱180/₱144) and sample posts
// (the CTransco/Sanait posts) — none of those exist in the real
// tabs. Every asserted fare comes from the built-in verified
// routes (Cabugao → Vigan ₱60/₱48) or from a seeded repository /
// seeded local storage; a different seed must (and does) render a
// different value.
import 'dart:convert';

import 'package:estudyantego/features/communities_tab.dart';
import 'package:estudyantego/features/community_post_repository.dart';
import 'package:estudyantego/features/community_posts.dart';
import 'package:estudyantego/features/fares_tab.dart';
import 'package:estudyantego/features/minecraft_theme.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_fakes.dart';

const _author = AuthUser(uid: 'author-1', email: 'author@example.com');
const _other = AuthUser(uid: 'other-1', email: 'other@example.com');

CommunityPost _shared({
  required String id,
  required String authorUid,
  required PostStatus status,
}) => CommunityPost(
  routeName: 'Cabugao → Vigan City',
  vehicles: const ['traditional-jeepney'],
  hours: '',
  fare: 0,
  hubName: 'Cabugao',
  from: 'Cabugao',
  to: 'Vigan City',
  faresByVehicle: const {'traditional-jeepney': 60},
  status: status,
  id: id,
  authorUid: authorUid,
  createdAt: DateTime(2026, 11, 2),
);

CommunityPost _local({String from = 'Vigan City', String to = 'Santa'}) =>
    CommunityPost(
      routeName: '$from → $to',
      vehicles: const ['modern-jeepney'],
      hours: '',
      fare: 0,
      hubName: 'Vigan City',
      from: from,
      to: to,
      faresByVehicle: const {'modern-jeepney': 30},
      status: PostStatus.approved,
    );

/// The blocky border width on a container's decoration (light
/// theme in these tests: 3px ink).
double? _borderWidth(BoxDecoration decoration) {
  final border = decoration.border;
  if (border is Border) return border.top.width;
  return null;
}

/// The nearest [MinecraftCard] ancestor of the widget showing
/// [text] — the post card itself, not the section shell it nests
/// inside (visitAncestorElements walks nearest-first).
Element _nearestMinecraftCard(WidgetTester tester, String text) {
  Element? found;
  tester.element(find.text(text)).visitAncestorElements((element) {
    if (element.widget is MinecraftCard) {
      found = element;
      return false;
    }
    return true;
  });
  expect(found, isNotNull, reason: 'no MinecraftCard ancestor of $text');
  return found!;
}

/// Asserts the nearest blocky card around [text] has the 3px ink
/// border.
void _expectBlockyCard(WidgetTester tester, String text) {
  final card = _nearestMinecraftCard(tester, text);
  final box =
      tester.widget<Container>(
            find.descendant(
              of: find.byElementPredicate((e) => e == card),
              matching: find.byType(Container),
            ).first,
          ).decoration
          as BoxDecoration;
  expect(_borderWidth(box), 3);
}

Future<void> _pumpFares(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    const MaterialApp(home: Scaffold(body: FaresTab())),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpCommunities(
  WidgetTester tester, {
  AuthUser? user,
  PostRepository? repository,
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CommunitiesTab(currentUser: user, postRepository: repository),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Fares tab — blocky fare cards (Feature 4)', () {
    testWidgets('fare cards render live fares, no sample fares', (
      tester,
    ) async {
      await _pumpFares(tester);
      // Live verified fare: Cabugao → Vigan ₱60 regular, ₱48 student.
      expect(find.text('Cabugao → Vigan Bus Terminal'), findsOneWidget);
      expect(find.text('₱60'), findsOneWidget);
      expect(find.text('₱48 student'), findsOneWidget);
      // The route card is a blocky Minecraft card: 3px ink border.
      final card = find.ancestor(
        of: find.text('Cabugao → Vigan Bus Terminal'),
        matching: find.byType(MinecraftCard),
      );
      expect(card, findsOneWidget);
      final cardBox =
          tester.widget<Container>(
                find.descendant(
                  of: card,
                  matching: find.byType(Container),
                ).first,
              ).decoration
              as BoxDecoration;
      expect(_borderWidth(cardBox), 3);
      // Baloo 2 route title.
      final title = tester.widget<Text>(
        find.text('Cabugao → Vigan Bus Terminal'),
      );
      expect(title.style?.fontFamily, startsWith('Baloo2'));
      // Real road detail from the live route data (hub distance),
      // never an invented number.
      expect(find.text('≈ 31.6 km road distance'), findsOneWidget);
      // The preview's sample fares never appear as real fares.
      expect(find.text('₱120'), findsNothing);
      expect(find.text('₱96'), findsNothing);
      expect(find.text('Vigan → Laoag'), findsNothing);
      // The Popular Routes header is a blocky section header.
      expect(find.byType(MinecraftSectionHeader), findsOneWidget);
      // Hero title is Baloo 2 on the grass block.
      final heroTitle = tester.widget<Text>(
        find.text('Know your fare before you go'),
      );
      expect(heroTitle.style?.fontFamily, startsWith('Baloo2'));
    });

    testWidgets('breakdown sheet shows the flat student discount card', (
      tester,
    ) async {
      await _pumpFares(tester);
      await tester.ensureVisible(find.text('Cabugao → Vigan Bus Terminal'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cabugao → Vigan Bus Terminal'));
      await tester.pumpAndSettle();
      expect(find.text('Fare breakdown'), findsOneWidget);
      // Flat (shadowless) discount note card: 20% off + school ID.
      // No fare amount is repeated here, so the sheet's ₱48 count
      // stays at the three discount rows.
      expect(find.byKey(const Key('student-discount-card')), findsOneWidget);
      expect(
        find.text(
          'Student discount: 20% off the regular fare — show your school ID.',
        ),
        findsOneWidget,
      );
      expect(find.text('₱48'), findsNWidgets(3));
      final discountCard = tester.widget<Container>(
        find.byKey(const Key('student-discount-card')),
      );
      final decoration = discountCard.decoration as BoxDecoration;
      expect(decoration.boxShadow, isNull);
      expect(_borderWidth(decoration), 3);
    });
  });

  group('Communities tab — blocky post cards (Feature 4)', () {
    testWidgets('post cards render live shared posts, no queue card', (
      tester,
    ) async {
      final repo = FakePostRepository();
      repo.stored.add(
        _shared(id: 's1', authorUid: 'x', status: PostStatus.approved),
      );
      await _pumpCommunities(tester, user: _other, repository: repo);
      expect(find.text('Cabugao → Vigan City'), findsOneWidget);
      // Live fare line from the seeded post, never a sample.
      expect(find.textContaining('₱60.00'), findsOneWidget);
      // The post card itself is a blocky Minecraft card (3px ink
      // border) with a Baloo 2 title — not just the section shell
      // it nests inside.
      _expectBlockyCard(tester, 'Cabugao → Vigan City');
      final title = tester.widget<Text>(find.text('Cabugao → Vigan City'));
      expect(title.style?.fontFamily, startsWith('Baloo2'));
      expect(find.text('Shared post'), findsOneWidget);
      // No own pending post: no queue card.
      expect(find.byKey(const Key('approval-queue-card')), findsNothing);
    });

    testWidgets('approval queue card shows for your own pending post', (
      tester,
    ) async {
      final repo = FakePostRepository();
      repo.stored.add(
        _shared(id: 's1', authorUid: 'author-1', status: PostStatus.pending),
      );
      await _pumpCommunities(tester, user: _author, repository: repo);
      expect(find.byKey(const Key('approval-queue-card')), findsOneWidget);
      expect(
        find.text(
          'Your post is in the queue — Waiting for admin approval before it publishes.',
        ),
        findsOneWidget,
      );
      expect(find.text('In Review'), findsOneWidget);
      // The pending post itself still renders as a blocky card.
      _expectBlockyCard(tester, 'Cabugao → Vigan City');
    });

    testWidgets('no queue card for another user\'s pending post', (
      tester,
    ) async {
      final repo = FakePostRepository();
      repo.stored.add(
        _shared(id: 's1', authorUid: 'author-1', status: PostStatus.pending),
      );
      // Another user cannot even see the pending post, so there is
      // no queue card for them either.
      await _pumpCommunities(tester, user: _other, repository: repo);
      expect(find.byKey(const Key('approval-queue-card')), findsNothing);
      expect(find.text('Cabugao → Vigan City'), findsNothing);
    });

    testWidgets('Like toggles red when liked on a local post', (
      tester,
    ) async {
      await _pumpCommunities(
        tester,
        user: _other,
        prefs: {
          samplePostSeededKey: true,
          communityPostsKey: jsonEncode([_local().toJson()]),
        },
      );
      expect(find.text('Vigan City → Santa'), findsOneWidget);
      expect(find.text('Local post'), findsOneWidget);
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(find.text('0'), findsNWidgets(3));
      final likeButton = find.ancestor(
        of: find.text('Like'),
        matching: find.byType(TextButton),
      );
      Color? likeColor() => tester
          .widget<TextButton>(likeButton)
          .style
          ?.foregroundColor
          ?.resolve({});
      // Unliked: the button is the neutral variant color, not red.
      expect(likeColor(), isNot(MinecraftColors.heartRed));

      await tester.tap(find.text('Like'));
      await tester.pumpAndSettle();
      // Liked: filled thumb + heart-red button.
      expect(find.byIcon(Icons.thumb_up), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(likeColor(), MinecraftColors.heartRed);

      // Toggle off again: back to outlined + neutral.
      await tester.tap(find.text('Like'));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.thumb_up_outlined), findsOneWidget);
      expect(likeColor(), isNot(MinecraftColors.heartRed));
    });
  });
}
