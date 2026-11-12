// Widget tests for the Minecraft theme audit (Builder 2).
//
// Asserts each newly themed page renders with Minecraft styling
// (MinecraftCard / MinecraftSectionHeader / Baloo 2 headings /
// grass block buttons) AND that its live data still renders.
// Every asserted value comes from the page's own inputs or seeded
// local records — nothing is invented here.
import 'package:estudyantego/features/about_screen.dart';
import 'package:estudyantego/features/app_layout.dart';
import 'package:estudyantego/features/app_reviews_admin_screen.dart';
import 'package:estudyantego/features/community_admin.dart';
import 'package:estudyantego/features/local_notifications.dart';
import 'package:estudyantego/features/minecraft_theme.dart';
import 'package:estudyantego/features/notification_settings_screen.dart';
import 'package:estudyantego/features/onboarding/onboarding_state.dart';
import 'package:estudyantego/features/onboarding/permission_service.dart';
import 'package:estudyantego/features/rewards_screen.dart';
import 'package:estudyantego/features/student/allowance_screen.dart';
import 'package:estudyantego/features/student/attendance_screen.dart';
import 'package:estudyantego/features/student/bible_screen.dart';
import 'package:estudyantego/features/student/commute_screen.dart';
import 'package:estudyantego/features/student/edit_school_calendar_screen.dart';
import 'package:estudyantego/features/student/quotes_screen.dart';
import 'package:estudyantego/features/student/student_data.dart';
import 'package:estudyantego/features/student/student_theme.dart';
import 'package:estudyantego/features/student/walking_goal_screen.dart';
import 'package:estudyantego/features/student/walking_repository.dart';
import 'package:estudyantego/features/student/walking_sensor.dart';
import 'package:estudyantego/features/student_id_card.dart';
import 'package:estudyantego/features/subscription_membership.dart';
import 'package:estudyantego/features/top_popup.dart';
import 'package:estudyantego/features/trips_tab.dart';
import 'package:estudyantego/features/friends_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void _tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(390, 6000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  _tallScreen(tester);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
}

/// Minimal permission fake for the notification settings screen.
class _FakePermissionService implements PermissionService {
  @override
  Future<NotificationPermissionStatus> notificationStatus() async =>
      NotificationPermissionStatus.granted;

  @override
  Future<NotificationPermissionStatus> requestNotification() async =>
      NotificationPermissionStatus.granted;

  @override
  Future<void> openAppSettings() async {}
}

/// Minimal scheduler fake: exact alarms allowed, nothing scheduled.
class _FakeScheduler implements NotificationScheduler {
  @override
  Future<bool> initialize({
    required String androidIcon,
    void Function(String? payload)? onTap,
  }) async => true;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    String? payload,
  }) async {}

  @override
  Future<void> zonedSchedule({
    required int id,
    String? title,
    String? body,
    required DateTime scheduledDate,
    String? payload,
    required NotificationRepeat repeat,
    required bool exact,
  }) async {}

  @override
  Future<void> cancelAll() async {}

  @override
  Future<bool> get canScheduleExact async => true;

  @override
  Future<void> requestExactAlarms() async {}
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Rewards Center full screen is Minecraft themed',
      (tester) async {
    await _pump(
      tester,
      RewardsScreen(pointsBalance: 120, onOpenStudentHub: () {}),
    );
    expect(find.byType(MinecraftCard), findsWidgets);
    expect(find.byType(MinecraftSectionHeader), findsWidgets);
    expect(find.text('120 points'), findsOneWidget);
    expect(find.text('Redeem all points'), findsOneWidget);
    expect(find.text('No redemptions yet.'), findsOneWidget);
  });

  testWidgets('About screen is Minecraft themed', (tester) async {
    await _pump(
      tester,
      AboutEstudyanteGOScreen(onBack: () {}),
    );
    expect(find.byType(MinecraftCard), findsOneWidget);
    expect(find.text('App stats'), findsOneWidget);
    expect(find.text('EstudyanteGO'), findsOneWidget);
    // Live counts from the built-in data (routes/hubs/cities).
    expect(find.byKey(const Key('about-stat-routes')), findsOneWidget);
    expect(find.byKey(const Key('about-stat-hubs')), findsOneWidget);
    expect(find.byKey(const Key('about-stat-cities')), findsOneWidget);
    // Version jump (Nov 12, 2026): 3.5.1, not 1.0.0.
    expect(
      find.text('Version 3.5.1 · com.estudyantego.app'),
      findsOneWidget,
    );
    expect(find.text('ESTUDYANTEGO · VERSION 3.5.1'), findsOneWidget);
  });

  testWidgets('Subscription Membership screen is Minecraft themed',
      (tester) async {
    await _pump(
      tester,
      SubscriptionMembershipScreen(onBack: () {}),
    );
    expect(find.byType(MinecraftCard), findsWidgets);
    expect(find.text('Free'), findsWidgets);
    expect(find.text('Current plan: Free — 2 GB storage'), findsOneWidget);
    expect(find.byKey(const Key('plan-card-free')), findsOneWidget);
    expect(find.byKey(const Key('plan-card-pro')), findsOneWidget);
  });

  testWidgets('Student ID card is Minecraft themed', (tester) async {
    await _pump(
      tester,
      const StudentIdCardScreen(
        profile: UserProfile(
          displayName: 'Test Student',
          email: 'test@example.com',
          school: 'University of Northern Philippines',
          program: 'DCT',
          year: '1st Year',
        ),
        onEditProfile: _noop,
      ),
    );
    expect(find.byType(MinecraftCard), findsWidgets);
    expect(find.text('Test Student'), findsOneWidget);
    expect(find.text('test@example.com'), findsOneWidget);
    expect(find.text('University of Northern Philippines'), findsOneWidget);
  });

  testWidgets('Edit School Calendar screen is Minecraft themed',
      (tester) async {
    await _pump(
      tester,
      const EditSchoolCalendarScreen(school: 'UNP', days: []),
    );
    expect(find.byType(MinecraftCard), findsOneWidget);
    expect(find.text('No marked days yet.'), findsOneWidget);
    // Baloo 2 section heading.
    final heading = tester.widget<Text>(find.text('Marked days'));
    expect(heading.style?.fontFamily, startsWith('Baloo2'));
  });

  testWidgets('Quotes screen is Minecraft themed', (tester) async {
    await _pump(tester, const QuotesScreen());
    expect(find.byType(MinecraftCard), findsWidgets);
    expect(find.byType(MinecraftSectionHeader), findsWidgets);
    expect(find.text('Quote of the Day'), findsOneWidget);
  });

  testWidgets('Bible screen is Minecraft themed', (tester) async {
    await _pump(tester, const BibleScreen());
    expect(find.byType(MinecraftCard), findsWidgets);
    expect(find.byType(MinecraftSectionHeader), findsWidgets);
    expect(find.text('Verse of the Day'), findsOneWidget);
  });

  testWidgets('Attendance screen is Minecraft themed', (tester) async {
    // Wide viewport: the filter dropdown row overflows at 390px
    // (pre-existing layout, also on the unthemed screen).
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: AttendanceScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MinecraftCard), findsWidgets);
    expect(find.text('No records found.'), findsOneWidget);
  });

  testWidgets('Commute screen is Minecraft themed', (tester) async {
    // Wide viewport: same pre-existing dropdown-row overflow as
    // Attendance at 390px.
    tester.view.physicalSize = const Size(800, 6000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CommuteScreen())),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MinecraftCard), findsWidgets);
    expect(find.byType(MinecraftSectionHeader), findsWidgets);
    expect(find.text('No saved routes yet.'), findsOneWidget);
  });

  testWidgets('Trips tab is Minecraft themed', (tester) async {
    await _pump(tester, const TripsTab());
    expect(find.byType(MinecraftCard), findsWidgets);
    expect(find.text('Find a Route'), findsOneWidget);
    final title = tester.widget<Text>(find.text('Find a Route'));
    expect(title.style?.fontFamily, startsWith('Baloo2'));
  });

  testWidgets('Community admin screen is Minecraft themed',
      (tester) async {
    await _pump(
      tester,
      CommunityAdminScreen(
        localPosts: const [],
        onLocalChanged: (_) {},
      ),
    );
    expect(find.byType(MinecraftSectionHeader), findsWidgets);
    // No repository: shared sections are unavailable, so only
    // the local sections render.
    expect(
      find.text('Local posts — Waiting Approval'),
      findsOneWidget,
    );
    expect(find.text('No local submissions waiting for review.'),
        findsOneWidget);
  });

  testWidgets('Notification Settings screen is Minecraft themed',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final service = LocalNotificationService(scheduler: _FakeScheduler());
    await service.initialize();
    tester.view.physicalSize = const Size(800, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: NotificationSettingsScreen(
            permissionService: _FakePermissionService(),
            notificationService: service,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MinecraftCard), findsWidgets);
    expect(find.text('Notification Settings'), findsOneWidget);
    expect(find.byKey(const Key('class-reminders-toggle')), findsOneWidget);
    expect(find.byKey(const Key('daily-login-toggle')), findsOneWidget);
  });

  testWidgets('Allowance screen is Minecraft themed', (tester) async {
    SharedPreferences.setMockInitialValues({
      StudentStorage.txnsKey: '[]',
      StudentStorage.goalsKey: '[]',
      StudentStorage.budgetsKey: '[]',
    });
    await _pump(tester, const AllowanceScreen());
    expect(find.byType(MinecraftCard), findsWidgets);
    expect(find.byType(MinecraftSectionHeader), findsWidgets);
    expect(find.text('Available balance'), findsOneWidget);
    expect(find.text('No savings goals yet.'), findsOneWidget);
    expect(find.text('New goal'), findsOneWidget);
  });

  testWidgets('Walking Goal permission message uses the block button',
      (tester) async {
    final controller = WalkingController(
      sensor: FakeWalkingSensor(),
      permission: FakeActivityPermission(
        current: ActivityPermissionStatus.denied,
      ),
    );
    await controller.init();
    addTearDown(controller.dispose);
    // pump(), not pumpAndSettle(): the screen never settles
    // (existing walking_goal_test pumps it the same way).
    _tallScreen(tester);
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: WalkingGoalScreen(controller: controller))),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Activity permission needed'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Allow activity tracking'),
    );
    expect(
      button.style?.backgroundColor?.resolve({}),
      MinecraftColors.grassGreen,
    );
  });

  testWidgets('App Reviews unavailable state still renders',
      (tester) async {
    await _pump(
      tester,
      const AppReviewsScreen(repository: null, adminEmail: null),
    );
    expect(
      find.text(
        'App reviews are unavailable — the app is not connected to Firebase.',
      ),
      findsOneWidget,
    );
  });

  test('Shared AppText headings are Baloo 2 (Minecraft audit)', () {
    // The shared scale used to be Plus Jakarta Sans; the audit
    // repointed every heading style at Baloo 2 (GoogleFonts runtime
    // download, family name 'Baloo2' plus a weight suffix).
    // Body styles stay const and inherit Nunito from the theme.
    expect(AppText.pageTitle.fontFamily, startsWith('Baloo2'));
    expect(AppText.titleLarge.fontFamily, startsWith('Baloo2'));
    expect(AppText.heading.fontFamily, startsWith('Baloo2'));
    expect(AppText.headingStrong.fontFamily, startsWith('Baloo2'));
    expect(AppText.sectionTitle.fontFamily, startsWith('Baloo2'));
    expect(AppText.cardTitle.fontFamily, startsWith('Baloo2'));
    expect(AppText.emptyTitle.fontFamily, startsWith('Baloo2'));
    expect(AppText.displaySmall.fontFamily, startsWith('Baloo2'));
    expect(AppText.bodyStrong.fontFamily, startsWith('Baloo2'));
    // Card radius matches the global Minecraft card theme (14px).
    expect(AppLayout.cardRadius, MinecraftShapes.cardRadius);
  });

  test('Student Hub theme derives from the Minecraft theme', () {
    // Light: grass primary, paper scaffold, white cards, Baloo 2
    // headings (was: deep-emerald primary, Inter body, Plus
    // Jakarta Sans headings, 20px/1px cards).
    final light = studentTheme;
    expect(light.colorScheme.primary, MinecraftColors.grassGreen);
    expect(light.scaffoldBackgroundColor, MinecraftColors.paper);
    expect(light.cardColor, Colors.white);
    expect(
      light.textTheme.titleLarge?.fontFamily,
      startsWith('Baloo2'),
    );
    expect(light.textTheme.bodyMedium?.fontFamily, startsWith('Nunito'));
    final cardShape = light.cardTheme.shape as RoundedRectangleBorder;
    expect(cardShape.borderRadius, BorderRadius.circular(14));
    // Dark: the same dark surfaces the Hub already used.
    final dark = studentDarkTheme;
    expect(dark.colorScheme.primary, MinecraftColors.grassGreen);
    expect(
      dark.scaffoldBackgroundColor,
      MinecraftColors.darkBackground,
    );
    expect(dark.cardColor, MinecraftColors.darkCard);
  });

  testWidgets('Friends section cards use the block shape',
      (tester) async {
    await _pump(tester, FriendsTab(codeGenerator: () => 'TEST-CODE'));
    // Section titles render in Baloo 2 via MinecraftText.title.
    final title = tester.widget<Text>(find.text('My Friends'));
    expect(title.style?.fontFamily, startsWith('Baloo2'));
    // The section card is a Card with the 14px / 3px block shape.
    final card = tester.widget<Card>(find.byType(Card).first);
    final shape = card.shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(14));
    expect(shape.side.width, MinecraftShapes.cardBorderWidth);
    expect(shape.side.color, MinecraftColors.border);
    // The friend code itself stays visible (local-only, no cloud).
    expect(find.text('TEST-CODE'), findsOneWidget);
  });

  testWidgets('TopPopup checkmark is the grass block', (tester) async {
    await _pump(
      tester,
      const TopPopup(
        progress: AlwaysStoppedAnimation<double>(0.5),
        title: 'Test title',
        message: 'Test message',
      ),
    );
    expect(find.text('Test title'), findsOneWidget);
    expect(find.text('Test message'), findsOneWidget);
    final checkCircle = tester.widget<Container>(
      find
          .ancestor(
            of: find.byIcon(Icons.check),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = checkCircle.decoration as BoxDecoration;
    expect(decoration.color, MinecraftColors.grassGreen);
    // The card keeps the 14px / 3px block shape in light mode: the
    // Material that wraps the popup's message text.
    final material = tester.widget<Material>(
      find
          .ancestor(
            of: find.text('Test message'),
            matching: find.byType(Material),
          )
          .first,
    );
    final shape = material.shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(14));
    expect(shape.side.width, MinecraftShapes.cardBorderWidth);
  });
}

void _noop() {}
