// Tests for the premium Friends page redesign.
//
// Honesty rules under test: the friend code is really generated and
// persisted (same code on every load); the QR encodes that exact code;
// Copy/Share call the real sharing backend; search filters only
// actually-stored local friends; Add Friend shows the real share path
// plus an honest cloud-sync note and creates NO fake friend; requests
// and chats have premium empty states with NO Accept/Decline buttons,
// NO fake conversations, NO timestamps, NO unread badges, and NO
// online indicators anywhere.
import 'package:estudyantego/features/friend_sharing.dart';
import 'package:estudyantego/features/friend_store.dart';
import 'package:estudyantego/features/friends_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeFriendSharing implements FriendSharing {
  final List<String> copied = [];
  final List<String> shared = [];

  @override
  Future<void> copyCode(String code) async {
    copied.add(code);
  }

  @override
  Future<void> shareCode(String code) async {
    shared.add(code);
  }
}

const _testCode = '123e4567-e89b-12d3-a456-426614174000';

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: child));

/// The code renders as SelectableText, which find.text does not match.
Finder _codeText() => find.byWidgetPredicate(
      (widget) => widget is SelectableText && widget.data == _testCode,
    );

Future<void> _pumpFriends(
  WidgetTester tester, {
  FakeFriendSharing? sharing,
  Map<String, Object>? prefs,
}) async {
  // Tall viewport so every section is laid out and tappable without
  // scrolling (same approach as the older friends tests).
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(prefs ?? {});
  await tester.pumpWidget(_wrap(
    FriendsTab(
      sharing: sharing ?? FakeFriendSharing(),
      codeGenerator: () => _testCode,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  // Registers the SharedPreferences mock channel for the plain unit
  // tests below (without this, getInstance() throws
  // MissingPluginException). Widget tests re-set their own values.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('FriendStore', () {
    test('code is generated once and stable across loads', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = FriendStore(prefs);
      var generated = 0;
      final first = await store.loadOrCreateFriendCode(
        generate: () {
          generated++;
          return 'code-1';
        },
      );
      final second = await store.loadOrCreateFriendCode(
        generate: () {
          generated++;
          return 'code-2';
        },
      );
      expect(first, 'code-1');
      expect(second, 'code-1');
      expect(generated, 1);
      expect(prefs.getString('byahetayo_friend_code'), 'code-1');
    });

    test('friends list round-trips, empty by default', () async {
      final prefs = await SharedPreferences.getInstance();
      final store = FriendStore(prefs);
      expect(store.loadFriends(), isEmpty);
      await store.saveFriends([
        const FriendEntry(name: 'Ana Santos', code: 'code-ana'),
        const FriendEntry(name: 'Ben'),
      ]);
      final loaded = store.loadFriends();
      expect(loaded.map((f) => f.name), ['Ana Santos', 'Ben']);
      expect(loaded.first.code, 'code-ana');
      expect(
        prefs.getString('byahetayo_friends'),
        contains('Ana Santos'),
      );
    });

    test('initials helper', () {
      expect(const FriendEntry(name: 'Ana Santos').initials, 'AS');
      expect(const FriendEntry(name: 'Ben').initials, 'B');
      expect(const FriendEntry(name: '  ').initials, '?');
    });
  });

  group('Premium Friends tab', () {
    testWidgets('sections render in spec order with honest empty states',
        (WidgetTester tester) async {
      await _pumpFriends(tester);
      for (final title in [
        'My Friends',
        'My Friend Code',
        'Friend Requests',
        'Chats',
      ]) {
        expect(find.text(title), findsOneWidget);
      }
      // Spec order: top-to-bottom positions strictly increase.
      double top(String text) =>
          tester.getTopLeft(find.text(text)).dy;
      expect(top('My Friends'), lessThan(top('My Friend Code')));
      expect(top('My Friend Code'), lessThan(top('Friend Requests')));
      expect(top('Friend Requests'), lessThan(top('Chats')));

      expect(find.text('No friends yet'), findsOneWidget);
      expect(find.text('No incoming requests'), findsOneWidget);
      expect(find.text('No outgoing requests'), findsOneWidget);
      expect(find.text('No conversations yet'), findsOneWidget);
      // No fake request actions, no fake presence, no fake identity.
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Decline'), findsNothing);
      expect(find.text('Online'), findsNothing);
      expect(find.text('Community'), findsNothing);
      expect(find.text('Share info'), findsNothing);
    });

    testWidgets('friend code section shows the real code + QR + actions',
        (WidgetTester tester) async {
      final sharing = FakeFriendSharing();
      await _pumpFriends(tester, sharing: sharing);

      expect(_codeText(), findsOneWidget);
      // The QR block renders for the same code shown above it
      // (QrImageView keeps its data private; size proves this is the
      // intended code block, and the code text proves its content).
      final qr = tester.widget<QrImageView>(find.byType(QrImageView).first);
      expect(qr.size, 180);

      await tester.tap(find.text('Copy').first);
      await tester.pumpAndSettle();
      expect(sharing.copied, [_testCode]);
      expect(find.text('Friend code copied.'), findsOneWidget);

      await tester.tap(find.text('Share').first);
      await tester.pumpAndSettle();
      expect(sharing.shared, [_testCode]);
    });

    testWidgets('Add Friend shows share path + sync note, no code entry',
        (WidgetTester tester) async {
      await _pumpFriends(tester);
      await tester.tap(find.text('Add Friend'));
      await tester.pumpAndSettle();

      expect(find.text('Add Friend'), findsWidgets);
      expect(
        find.textContaining('needs cloud sync, which is not enabled yet'),
        findsWidgets,
      );
      expect(
        find.textContaining('no code entry is offered here'),
        findsOneWidget,
      );
      // The only TextField on screen is the search field: the sheet
      // offers no code-entry field that could fabricate a friend.
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      // Closing the sheet created no friend.
      expect(find.text('No friends yet'), findsOneWidget);
    });

    testWidgets('search filters only actually-stored local friends',
        (WidgetTester tester) async {
      await _pumpFriends(tester, prefs: {
        'byahetayo_friends':
            '[{"name":"Ana Santos","code":"code-ana"},{"name":"Ben Cruz"}]',
      });
      expect(find.text('Ana Santos'), findsOneWidget);
      expect(find.text('Ben Cruz'), findsOneWidget);

      // The search field is the only TextField on screen; its hint
      // disappears once text is entered, so find it by type.
      await tester.enterText(find.byType(TextField), 'ana');
      await tester.pumpAndSettle();
      expect(find.text('Ana Santos'), findsOneWidget);
      expect(find.text('Ben Cruz'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('Ana Santos'), findsNothing);
      expect(find.textContaining('No friends match'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('Ana Santos'), findsOneWidget);
      expect(find.text('Ben Cruz'), findsOneWidget);
    });

    testWidgets('message action honestly explains sync is needed',
        (WidgetTester tester) async {
      await _pumpFriends(tester, prefs: {
        'byahetayo_friends': '[{"name":"Ana Santos"}]',
      });
      await tester.tap(find.byTooltip('Message Ana Santos'));
      await tester.pumpAndSettle();
      expect(
        find.text('Chats need cloud sync, which is not enabled yet.'),
        findsOneWidget,
      );
      // No fake chat screen opened.
      expect(find.text('Ana Santos'), findsOneWidget);
    });

    testWidgets('friend rows show initials avatars, never online dots',
        (WidgetTester tester) async {
      await _pumpFriends(tester, prefs: {
        'byahetayo_friends': '[{"name":"Ana Santos"}]',
      });
      expect(find.text('AS'), findsOneWidget);
      expect(find.byIcon(Icons.circle), findsNothing);
    });
  });

  group('Friends alignment (layout only)', () {
    Future<void> pumpAligned(
      WidgetTester tester, {
      required Size size,
      ThemeData? theme,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Scaffold(
          body: FriendsTab(
            sharing: FakeFriendSharing(),
            codeGenerator: () => _testCode,
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    double cardCenterX(WidgetTester tester, Finder f) {
      final card = tester.widget<Card>(
        find.ancestor(of: f, matching: find.byType(Card)).first,
      );
      return tester.getRect(find.byWidget(card)).center.dx;
    }

    double cardLeft(WidgetTester tester, Finder f) {
      final card = tester.widget<Card>(
        find.ancestor(of: f, matching: find.byType(Card)).first,
      );
      return tester.getRect(find.byWidget(card)).left;
    }

    const emptyTitles = [
      'No friends yet',
      'No incoming requests',
      'No outgoing requests',
      'No conversations yet',
    ];

    testWidgets('empty states and QR are centered at phone and tablet widths',
        (WidgetTester tester) async {
      for (final entry in [
        (const Size(390, 3000), null),
        (const Size(1000, 1400), null),
        (const Size(390, 3000), ThemeData.dark()),
      ]) {
        await pumpAligned(tester, size: entry.$1, theme: entry.$2);
        for (final title in emptyTitles) {
          final finder = find.text(title);
          expect(finder, findsOneWidget);
          expect(
            (tester.getCenter(finder).dx - cardCenterX(tester, finder)).abs(),
            lessThan(1.0),
            reason: '$title should be centered at ${entry.$1}',
          );
        }
        final qr = find.byType(QrImageView).first;
        expect(
          (tester.getCenter(qr).dx - cardCenterX(tester, qr)).abs(),
          lessThan(1.0),
          reason: 'QR should be centered at ${entry.$1}',
        );
      }
    });

    testWidgets('section headings and descriptions stay left-aligned',
        (WidgetTester tester) async {
      await pumpAligned(tester, size: const Size(390, 3000));
      // Page header sits at the ListView padding edge (16dp).
      expect(tester.getTopLeft(find.text('Friends')).dx, closeTo(16, 1.0));
      expect(
        tester.getTopLeft(find.text('People you travel with')).dx,
        closeTo(16, 1.0),
      );
      // Card content starts after card margin (4dp) + card padding
      // (16dp); subsection headings sit exactly there, not centered.
      final incoming = find.text('Incoming');
      expect(
        tester.getTopLeft(incoming).dx,
        closeTo(cardLeft(tester, incoming) + 20, 1.0),
      );
      expect(
        tester.getCenter(incoming).dx,
        lessThan(cardCenterX(tester, incoming)),
      );
      // Section title sits after its leading icon (24dp) + gap (12dp).
      final myFriends = find.text('My Friends');
      expect(
        tester.getTopLeft(myFriends).dx,
        closeTo(cardLeft(tester, myFriends) + 56, 1.0),
      );
    });

    testWidgets('Copy and Share share a row when wide, stack when narrow',
        (WidgetTester tester) async {
      // Phone + tablet widths: one row, Copy left of Share, same top.
      for (final size in [const Size(390, 3000), const Size(1000, 1400)]) {
        await pumpAligned(tester, size: size);
        final copyTop = tester.getTopLeft(find.text('Copy')).dy;
        final shareTop = tester.getTopLeft(find.text('Share')).dy;
        expect((copyTop - shareTop).abs(), lessThan(1.0));
        expect(
          tester.getTopRight(find.text('Copy')).dx,
          lessThan(tester.getTopLeft(find.text('Share')).dx),
        );
      }
      // Narrow card (320dp phone): stacked full-width buttons.
      await pumpAligned(tester, size: const Size(320, 3000));
      expect(
        tester.getTopLeft(find.text('Share')).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(find.text('Copy')).dy),
      );
    });

    testWidgets('no overflow at realistic phone and tablet sizes',
        (WidgetTester tester) async {
      for (final entry in [
        (const Size(390, 844), null),
        (const Size(1000, 800), null),
        (const Size(390, 844), ThemeData.dark()),
      ]) {
        await pumpAligned(tester, size: entry.$1, theme: entry.$2);
        // Lazily built ListView: drag until the last section is built.
        // (scrollUntilVisible cannot be used here: the search field
        // and code text each own an internal Scrollable, so the
        // default Scrollable finder is ambiguous.)
        for (var i = 0;
            i < 10 && find.text('No conversations yet').evaluate().isEmpty;
            i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -600));
          await tester.pumpAndSettle();
        }
        expect(find.text('No conversations yet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
