import 'dart:convert';

import 'package:estudyantego/features/community_posts.dart';
import 'package:estudyantego/features/communities_tab.dart';
import 'package:estudyantego/features/onboarding/auth_service.dart';

import 'test_fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('community form requires From and To', () {
    expect(
      communityFormError(
        from: '',
        to: 'Vigan City',
        vehicles: ['traditional-jeepney'],
        fareTexts: {'traditional-jeepney': '60'},
      ),
      'Add a starting location (From) for this route.',
    );
    expect(
      communityFormError(
        from: 'Cabugao',
        to: '   ',
        vehicles: ['traditional-jeepney'],
        fareTexts: {'traditional-jeepney': '60'},
      ),
      'Add a destination (To) for this route.',
    );
  });

  test('community form requires at least one vehicle', () {
    expect(
      communityFormError(
        from: 'Cabugao',
        to: 'Vigan City',
        vehicles: [],
        fareTexts: {},
      ),
      'Pick at least one vehicle type.',
    );
  });

  test('community form requires a fare above zero per vehicle', () {
    expect(
      communityFormError(
        from: 'Cabugao',
        to: 'Vigan City',
        vehicles: ['traditional-jeepney'],
        fareTexts: {'traditional-jeepney': ''},
      ),
      'Add a fare above ₱0 for Traditional Jeepney.',
    );
    expect(
      communityFormError(
        from: 'Cabugao',
        to: 'Vigan City',
        vehicles: ['traditional-jeepney'],
        fareTexts: {'traditional-jeepney': 'abc'},
      ),
      'Add a fare above ₱0 for Traditional Jeepney.',
    );
    expect(
      communityFormError(
        from: 'Cabugao',
        to: 'Vigan City',
        vehicles: ['traditional-jeepney'],
        fareTexts: {'traditional-jeepney': '0'},
      ),
      'Add a fare above ₱0 for Traditional Jeepney.',
    );
    expect(
      communityFormError(
        from: 'Cabugao',
        to: 'Vigan City',
        vehicles: ['traditional-jeepney'],
        fareTexts: {'traditional-jeepney': '60'},
      ),
      isNull,
    );
  });

  test('community form flags the vehicle missing a fare', () {
    expect(
      communityFormError(
        from: 'Cabugao',
        to: 'Vigan City',
        vehicles: ['traditional-jeepney', 'modern-jeepney'],
        fareTexts: {'traditional-jeepney': '60'},
      ),
      'Add a fare above ₱0 for Modern Jeepney.',
    );
  });

  test('community post survives a save/load round trip', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const post = CommunityPost(
      routeName: 'Cabugao → Vigan City',
      from: 'Cabugao',
      to: 'Vigan City',
      vehicles: ['traditional-jeepney', 'modern-jeepney'],
      hours: '6:00 PM – 9:00 PM',
      fare: 0,
      hubName: 'Cabugao',
      photoBase64: 'aGVsbG8=',
      faresByVehicle: {'traditional-jeepney': 60, 'modern-jeepney': 65},
      operatorName: 'CTransco',
      status: PostStatus.pending,
    );
    await saveCommunityPosts(prefs, [post]);
    final loaded = await loadCommunityPosts(prefs);
    expect(loaded.length, 1);
    expect(loaded.first.displayTitle, 'Cabugao → Vigan City');
    expect(loaded.first.from, 'Cabugao');
    expect(loaded.first.to, 'Vigan City');
    expect(
      loaded.first.vehicles,
      ['traditional-jeepney', 'modern-jeepney'],
    );
    expect(loaded.first.faresByVehicle['traditional-jeepney'], 60);
    expect(loaded.first.faresByVehicle['modern-jeepney'], 65);
    expect(loaded.first.operatorName, 'CTransco');
    expect(loaded.first.status, PostStatus.pending);
    expect(loaded.first.hubName, 'Cabugao');
    expect(loaded.first.photoBase64, 'aGVsbG8=');
    expect(base64Decode(loaded.first.photoBase64!), [104, 101, 108, 108, 111]);
  });

  test('community post description survives a save/load round trip',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const post = CommunityPost(
      routeName: 'Cabugao → Vigan City',
      from: 'Cabugao',
      to: 'Vigan City',
      vehicles: ['traditional-jeepney'],
      hours: '',
      fare: 0,
      hubName: 'Cabugao',
      faresByVehicle: {'traditional-jeepney': 60},
      description: 'Fare and transport info for commuters.',
      status: PostStatus.approved,
    );
    await saveCommunityPosts(prefs, [post]);
    final loaded = await loadCommunityPosts(prefs);
    expect(loaded.length, 1);
    expect(
      loaded.first.description,
      'Fare and transport info for commuters.',
    );
    expect(loaded.first.hasDescription, isTrue);
    // copyWith keeps the description unless replaced.
    expect(
      post.copyWith().description,
      'Fare and transport info for commuters.',
    );
    expect(post.copyWith(description: 'New text').description, 'New text');
  });

  test('community post without a description has none to show', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const post = CommunityPost(
      routeName: 'Cabugao → Vigan City',
      from: 'Cabugao',
      to: 'Vigan City',
      vehicles: ['traditional-jeepney'],
      hours: '',
      fare: 0,
      hubName: 'Cabugao',
      faresByVehicle: {'traditional-jeepney': 60},
      status: PostStatus.approved,
    );
    // A whitespace-only description counts as no description.
    const blank = CommunityPost(
      routeName: 'Cabugao → Vigan City',
      from: 'Cabugao',
      to: 'Vigan City',
      vehicles: ['traditional-jeepney'],
      hours: '',
      fare: 0,
      hubName: 'Cabugao',
      faresByVehicle: {'traditional-jeepney': 60},
      description: '   ',
      status: PostStatus.approved,
    );
    await saveCommunityPosts(prefs, [post, blank]);
    final loaded = await loadCommunityPosts(prefs);
    expect(loaded.length, 2);
    expect(loaded[0].description, isEmpty);
    expect(loaded[0].hasDescription, isFalse);
    expect(loaded[1].hasDescription, isFalse);
    // The stored JSON omits an empty description entirely.
    expect(post.toJson().containsKey('description'), isFalse);
    expect(blank.toJson().containsKey('description'), isFalse);
  });

  test('community load keeps legacy posts without From/To', () async {
    // Stored JSON from before approval existed: no 'status' key.
    SharedPreferences.setMockInitialValues({
      communityPostsKey: jsonEncode([
        {
          'routeName': 'Cabugao night jeepney',
          'vehicles': ['Jeepney'],
          'hours': '',
          'fare': 60,
          'hubName': 'Cabugao',
        },
      ]),
    });
    final prefs = await SharedPreferences.getInstance();
    final loaded = await loadCommunityPosts(prefs);
    expect(loaded.length, 1);
    expect(loaded.first.displayTitle, 'Cabugao night jeepney');
    expect(loaded.first.from, isEmpty);
    // Legacy posts predate approval: grandfathered in as approved,
    // and their single fare still shows as the legacy fare line.
    expect(loaded.first.status, PostStatus.approved);
    expect(loaded.first.fareLines, ['Fare: ₱60.00']);
  });

  test('community status parsing defaults safely', () {
    expect(postStatusFromString(null), PostStatus.approved);
    expect(postStatusFromString('approved'), PostStatus.approved);
    expect(postStatusFromString('pending'), PostStatus.pending);
    expect(postStatusFromString('rejected'), PostStatus.rejected);
    // Unknown stored values never auto-publish.
    expect(postStatusFromString('bogus'), PostStatus.pending);
  });

  test('community fare lines prefer per-vehicle fares', () {
    const post = CommunityPost(
      routeName: 'Cabugao → Vigan City',
      from: 'Cabugao',
      to: 'Vigan City',
      vehicles: ['traditional-jeepney', 'modern-jeepney'],
      hours: '',
      fare: 0,
      hubName: 'Cabugao',
      faresByVehicle: {'traditional-jeepney': 60, 'modern-jeepney': 65},
    );
    expect(post.fareLines, [
      'Traditional Jeepney: ₱60.00',
      'Modern Jeepney: ₱65.00',
    ]);
    const legacy = CommunityPost(
      routeName: 'Old route',
      vehicles: ['Jeepney'],
      hours: '',
      fare: 60,
      hubName: 'Cabugao',
    );
    expect(legacy.fareLines, ['Fare: ₱60.00']);
    const noFare = CommunityPost(
      routeName: 'No fare route',
      vehicles: ['tricycle'],
      hours: '',
      fare: 0,
      hubName: 'Cabugao',
    );
    expect(noFare.fareLines, isEmpty);
  });

  test('community list hides rejected posts only', () {
    const pending = CommunityPost(
      routeName: 'A',
      vehicles: [],
      hours: '',
      fare: 0,
      hubName: 'Cabugao',
      status: PostStatus.pending,
    );
    const approved = CommunityPost(
      routeName: 'B',
      vehicles: [],
      hours: '',
      fare: 0,
      hubName: 'Cabugao',
      status: PostStatus.approved,
    );
    const rejected = CommunityPost(
      routeName: 'C',
      vehicles: [],
      hours: '',
      fare: 0,
      hubName: 'Cabugao',
      status: PostStatus.rejected,
    );
    expect(showPostInCommunityList(pending), isTrue);
    expect(showPostInCommunityList(approved), isTrue);
    expect(showPostInCommunityList(rejected), isFalse);
  });

  test('community load skips corrupt entries instead of crashing', () async {
    SharedPreferences.setMockInitialValues({
      communityPostsKey: 'not-json-at-all',
    });
    final prefs = await SharedPreferences.getInstance();
    expect(await loadCommunityPosts(prefs), isEmpty);
  });

  test('legacy local sample is removed, sample lives in Firestore only',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final other = CommunityPost(
      routeName: 'Vigan City → Santa',
      vehicles: ['modern-jeepney'],
      hours: '',
      fare: 0,
      hubName: 'Vigan City',
      from: 'Vigan City',
      to: 'Santa',
      faresByVehicle: {'modern-jeepney': 30},
    );
    final result = await removeLegacyLocalSample(
      prefs,
      [sampleCommunityPost, other],
    );
    expect(result.length, 1);
    expect(result.first.to, 'Santa');
    expect(prefs.getBool(samplePostSeededKey), isTrue);
    // Removal persisted and never brings the sample back.
    final again = await removeLegacyLocalSample(
      prefs,
      await loadCommunityPosts(prefs),
    );
    expect(again.length, 1);
    expect(again.first.to, 'Santa');
  });

  test('no local sample means nothing to remove', () async {
    SharedPreferences.setMockInitialValues({samplePostSeededKey: true});
    final prefs = await SharedPreferences.getInstance();
    final result = await removeLegacyLocalSample(prefs, []);
    expect(result, isEmpty);
  });

  testWidgets('community create form validates and the shared post appears', (
    tester,
  ) async {
    // Seed flag set so the sample does not appear in this flow test.
    SharedPreferences.setMockInitialValues({samplePostSeededKey: true});
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const user = AuthUser(uid: 'u1', email: 'user@example.com');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunitiesTab(
            currentUser: user,
            postRepository: FakePostRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No announcements or posts yet.'), findsOneWidget);
    await tester.tap(find.text('Share info'));
    await tester.pumpAndSettle();
    expect(find.text('Share a route'), findsOneWidget);
    // Empty save shows the From validation first.
    await tester.tap(find.text('Share post'));
    await tester.pumpAndSettle();
    expect(
      find.text('Add a starting location (From) for this route.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).at(0), 'Cabugao');
    await tester.tap(find.text('Share post'));
    await tester.pumpAndSettle();
    expect(
      find.text('Add a destination (To) for this route.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).at(1), 'Vigan City');
    await tester.tap(find.text('Share post'));
    await tester.pumpAndSettle();
    expect(find.text('Pick at least one vehicle type.'), findsOneWidget);
    await tester.tap(find.text('Traditional Jeepney'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share post'));
    await tester.pumpAndSettle();
    expect(
      find.text('Add a fare above ₱0 for Traditional Jeepney.'),
      findsOneWidget,
    );
    // Field order: From, To, per-vehicle fare, hours, operator,
    // description. The description is optional.
    await tester.enterText(find.byType(TextField).at(2), '60');
    await tester.enterText(
      find.byType(TextField).at(5),
      'Fare and transport info for commuters.',
    );
    await tester.tap(find.text('Share post'));
    await tester.pumpAndSettle();
    expect(find.text('Cabugao → Vigan City'), findsOneWidget);
    expect(find.text('Shared post'), findsOneWidget);
    expect(find.text('In Review'), findsOneWidget);
    expect(find.text('Traditional Jeepney: ₱60.00'), findsOneWidget);
    expect(find.text('Description'), findsOneWidget);
    expect(
      find.text('Fare and transport info for commuters.'),
      findsOneWidget,
    );
    expect(find.text('View Route'), findsOneWidget);
    expect(find.text('View on map'), findsOneWidget);
  });

  testWidgets('community View Route opens the details view', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({samplePostSeededKey: true});
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const user = AuthUser(uid: 'u1', email: 'user@example.com');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommunitiesTab(
            currentUser: user,
            postRepository: FakePostRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share info'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Cabugao');
    await tester.enterText(find.byType(TextField).at(1), 'Vigan City');
    await tester.tap(find.text('Traditional Jeepney'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(2), '60');
    await tester.tap(find.text('Share post'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View Route'));
    await tester.pumpAndSettle();
    // Details view: labeled From/To/Fare rows (card has no such labels).
    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Fare'), findsOneWidget);
    expect(find.textContaining('₱60'), findsWidgets);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(find.text('From'), findsNothing);
  });

  testWidgets('sample post does not appear locally on first launch', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CommunitiesTab())),
    );
    await tester.pumpAndSettle();
    // Database-only sample: no local card on a signed-out first
    // launch, and the honest empty state instead.
    expect(find.text('Vigan City → Cabugao'), findsNothing);
    expect(find.text('In Review'), findsNothing);
    expect(find.text('Operator: CTransco'), findsNothing);
    expect(find.text('Modern Jeepney: ₱60.00'), findsNothing);
    expect(find.text('No announcements or posts yet.'), findsOneWidget);
  });
}
