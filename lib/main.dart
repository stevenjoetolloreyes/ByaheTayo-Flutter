// EstudyanteGO — Flutter foundation.
//
// Single codebase for Android, iOS and tablets. This file owns only the
// app shell: Material 3 theme (EstudyanteGO brand), adaptive navigation,
// tab state preservation, and the first-time gate (splash → onboarding
// → sign-in → email verification → profile setup → dashboard).
// Feature ports land in their own files under lib/features/ and plug
// into the tab shells below — no tab is a dummy page.
//
// Wide layout (width >= 600, tablet portrait + landscape) uses a
// collapsible left sidebar (220dp expanded / 80dp collapsed, preference
// saved locally). Phones (width < 600) use the plain "EstudyanteGO"
// wordmark header + the Facebook-style icon-only top nav (Student is
// the default tab); there is no bottom nav on phones. The Account tab
// is the premium dashboard in
// lib/features/account_tab.dart. The Fares tab is a real calculator in
// lib/features/fares_tab.dart.
//
// First-time logic (see lib/features/onboarding/onboarding_state.dart):
// onboarding shows only on first install; a returning user with an
// active Firebase session goes straight to the dashboard; without a
// session they go to Sign In; incomplete registration resumes at the
// right setup step. When Firebase is NOT configured yet (no
// google-services.json), auth gating is skipped and the dashboard
// opens after onboarding, so the app stays usable before setup.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/diagnostics/diagnostics.dart';

import 'features/account_tab.dart';
import 'features/ad_service.dart';
import 'features/app_layout.dart';
import 'features/app_rating_overlay.dart';
import 'features/app_reply_popup.dart';
import 'features/app_review_notifications.dart';
import 'features/chat_support.dart';
import 'features/chat_support_screen.dart';
import 'features/support_reply_popup.dart';
import 'features/bus_companies.dart';
import 'features/bus_stops.dart';
import 'features/communities_tab.dart';
import 'features/community_post_repository.dart';
import 'features/credits_repository.dart';
import 'features/custom_routes.dart';
import 'features/fares_tab.dart';
import 'features/friend_cloud_repository.dart';
import 'features/hidden_routes.dart';
import 'features/ios_components.dart';
import 'features/minecraft_tap_animation.dart';
import 'features/minecraft_theme.dart';
import 'features/onboarding/splash_sound.dart';
import 'features/local_notifications.dart';
import 'features/route_fare_overrides.dart';
import 'features/security/login_alert_dialog.dart';
import 'features/security/session_models.dart';
import 'features/security/session_repository.dart';
import 'features/security/session_service.dart';
import 'features/shared_study_files.dart';
import 'features/map_tab.dart';
import 'features/study_tab.dart';
import 'features/subscription_membership.dart';
import 'features/top_nav.dart';
import 'features/onboarding/auth_screen.dart';
import 'features/onboarding/auth_service.dart';
import 'features/onboarding/firebase_auth_service.dart';
import 'features/onboarding/firebase_init.dart';
import 'features/onboarding/notification_prompt.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/points_wallet_repository.dart';
import 'features/profile_repository.dart';
import 'features/onboarding/onboarding_state.dart';
import 'features/onboarding/permission_service.dart';
import 'features/onboarding/profile_setup_screen.dart';
import 'features/onboarding/setup_celebration.dart';
import 'features/onboarding/splash_screen.dart';
import 'features/onboarding/verify_email_screen.dart';
import 'features/onboarding/welcome_back_overlay.dart';
import 'features/profile_avatar.dart';
import 'features/student_tab.dart';
import 'features/student/allowance_screen.dart';
import 'features/student/allowance_widget_service.dart';
import 'features/student/classes_screen.dart';
import 'features/student/daily_quotes_widget_service.dart';
import 'features/student/fares_widget_service.dart';
import 'features/student/quotes_screen.dart';
import 'features/student/schedule_widget_service.dart';
import 'features/student/tasks_widget_service.dart';
import 'features/student/student_theme.dart';
import 'features/student/watch_tour.dart';
import 'theme_preference.dart';

/// SharedPreferences key for the sidebar collapsed state.
const _sidebarCollapsedKey = 'byahetayo_sidebar_collapsed';

/// SharedPreferences key for the theme preference
/// ('system', 'light', 'dark', 'timeBased' — see theme_preference.dart).
const _themeModeKey = 'byahetayo_theme_mode';

/// Production-safe startup with the ONE diagnostics system.
///
/// Stage order: binding -> prefs -> Firebase (+ App Check, reported
/// separately via its callback) -> runApp (zone-guarded). Every
/// recoverable stage failure is recorded and falls back instead of
/// throwing: prefs failure falls back to default theme/sidebar,
/// Firebase failure falls back to the existing unconfigured path
/// (auth gate skipped, as before). Safe Mode skips only nonessential
/// services (App Check activation); it never skips auth, profile,
/// onboarding, prefs, or Firebase core init, and never clears state.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final diagnosticsService = ErrorLogService.instance;
  // Diagnostics store: primary JSON-lines file in documents, plus the
  // external mirror file the File Manager can open (same JSON format,
  // one system — this replaces the earlier plain-text file-logger).
  // Every step is guarded: a diagnostics failure can never break
  // startup.
  try {
    final docs = await getApplicationDocumentsDirectory();
    final external = await getExternalStorageDirectory();
    await diagnosticsService.init(
      store: ErrorLogStore(
        storage: FileErrorLogStorage(File('${docs.path}/error_logs.jsonl')),
        externalMirrorFile: external == null
            ? null
            : File('${external.path}/estudyantego-crash.log'),
      ),
    );
  } catch (_) {
    // Diagnostics unavailable; startup continues without it.
  }
  diagnosticsService.installFlutterErrorHandler();
  final diagnostics = diagnosticsService.diagnostics;
  if (diagnostics != null) {
    // Binding succeeded if execution reached here; record it as a
    // completed stage (start + end) for a consistent stage timeline.
    await diagnostics.startStage(StartupStage.flutterBinding);
    await diagnostics.endStage(StartupStage.flutterBinding, success: true);
  }

  // Retry handler for the Diagnostics screen's Retry button: re-runs
  // only the safe, re-runnable stages (prefs + Firebase). It never
  // restarts the app, never clears session or onboarding progress,
  // and never navigates.
  diagnosticsService.onRetryRequested = () async {
    final d = diagnosticsService.diagnostics;
    if (d == null) return;
    await d.runStage<SharedPreferences?>(
      StartupStage.sharedPreferences,
      SharedPreferences.getInstance,
      fallback: null,
      timeout: const Duration(seconds: 10),
    );
    await d.runStage<bool>(
      StartupStage.firebase,
      () => initializeFirebase(
        skipAppCheck: d.safeMode,
        onAppCheckResult: (succeeded) {
          unawaited(
            diagnosticsService.record(
              category: ErrorCategory.startup,
              message: succeeded
                  ? 'App Check activation succeeded.'
                  : 'App Check activation did not complete '
                        '(best-effort; launch continues).',
              startupStage: StartupStage.appCheck.name,
              severity: succeeded ? ErrorSeverity.info : ErrorSeverity.warning,
            ),
          );
        },
      ),
      fallback: false,
      timeout: const Duration(seconds: 20),
    );
  };

  // SharedPreferences stage: timeout + fallback to defaults.
  // (The original code awaited getInstance() unguarded; a prefs
  // failure previously left startup hanging. The fallback preserves
  // the old defaults exactly: sidebar expanded, dark theme
  // (the preview default, Nov 7).)
  final SharedPreferences? prefs;
  if (diagnostics != null) {
    prefs = await diagnostics.runStage<SharedPreferences?>(
      StartupStage.sharedPreferences,
      SharedPreferences.getInstance,
      fallback: null,
      timeout: const Duration(seconds: 10),
    );
  } else {
    prefs = await SharedPreferences.getInstance();
  }

  // Firebase stage: initializeFirebase() itself never throws (it
  // returns false on any failure); the timeout wrapper adds the
  // stage-timeout protection on top of that existing guard.
  final bool firebaseConfigured;
  if (diagnostics != null) {
    firebaseConfigured = await diagnostics.runStage<bool>(
      StartupStage.firebase,
      () => initializeFirebase(
        skipAppCheck: diagnostics.safeMode,
        onAppCheckResult: (succeeded) {
          unawaited(
            diagnosticsService.record(
              category: ErrorCategory.startup,
              message: succeeded
                  ? 'App Check activation succeeded.'
                  : 'App Check activation did not complete '
                        '(best-effort; launch continues).',
              startupStage: StartupStage.appCheck.name,
              severity: succeeded ? ErrorSeverity.info : ErrorSeverity.warning,
            ),
          );
        },
      ),
      fallback: false,
      timeout: const Duration(seconds: 20),
    );
  } else {
    // Guarded: false when google-services.json is missing or Firebase
    // fails to start. The app never crashes over Firebase setup.
    firebaseConfigured = await initializeFirebase();
  }

  runZonedGuarded(() {
    // Theme preference is read once at startup; Time Based resolves
    // against the clock right now and re-evaluates while running
    // (resume + periodic check in _EstudyanteGOAppState).
    final themePreference = appThemePreferenceFromString(
      prefs?.getString(_themeModeKey),
    );
    runApp(
      EstudyanteGOApp(
        initialSidebarCollapsed: prefs?.getBool(_sidebarCollapsedKey) ?? false,
        initialThemePreference: themePreference,
        initialThemeMode: resolveThemeMode(themePreference, DateTime.now()),
        authService: FirebaseAuthService(isConfigured: firebaseConfigured),
      ),
    );
    unawaited(
      diagnosticsService.record(
        category: ErrorCategory.startup,
        message: 'runApp called.',
        severity: ErrorSeverity.info,
      ),
    );
  }, diagnosticsService.handleZoneError);
}

// ---- Brand — Minecraft theme (Feature 1) ----
// The dark emerald brand green is present as the Minecraft palette
// itself: grass green #58CC02 over deep leaves #2F7A12 (see
// lib/features/minecraft_theme.dart). The old Premium Dark
// Minimalist tokens are gone; the dark-mode surfaces live in
// MinecraftColors now.
const _textSecondary = Color(0xFF5B6B52);

// Minecraft theme foundation (Feature 1): the global light + dark
// themes are built from the Minecraft tokens in
// lib/features/minecraft_theme.dart (grass green primary, Baloo 2
// headings, Nunito body, blocky 3px borders + hard shadows). The
// iOS-style Cupertino override stays here — it is shell behavior,
// not a Minecraft token.
ThemeData _lightTheme() => minecraftThemeData(Brightness.light).copyWith(
  cupertinoOverrideTheme: iosCupertinoTheme(Brightness.light).noDefault(),
);

ThemeData _darkTheme() => minecraftThemeData(Brightness.dark).copyWith(
  cupertinoOverrideTheme: iosCupertinoTheme(Brightness.dark).noDefault(),
);

// ---- Destinations (6 tabs) ----
// Order (preview parity, Nov 6): Student, Study, Fares, Map,
// Communities, Account. Student is the DEFAULT tab on open
// (index 0). Friends is NOT a tab anymore: it moved into the
// Account tab's Quick Actions (preview: tapping the tile opens
// the Friends screen with its content untouched).
class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const _destinations = <_Destination>[
  _Destination('Student', Icons.school_outlined, Icons.school),
  _Destination('Study', Icons.menu_book_outlined, Icons.menu_book),
  _Destination('Fares', Icons.payments_outlined, Icons.payments),
  _Destination('Map', Icons.map_outlined, Icons.map),
  _Destination('Communities', Icons.groups_outlined, Icons.groups),
  _Destination('Account', Icons.person_outlined, Icons.person),
];

/// Which post-setup overlay the gate shows after a new user taps
/// "Finish setup" (Feature 2). The overlays are part of the
/// onboarding flow, not new steps — the 9-step stepper stays as-is.
enum _PostSetupPhase {
  /// No overlay: the normal Profile Setup screen.
  none,

  /// Celebration overlay (auto-advances, or tap to skip).
  celebration,

  /// "You know how to use the app?" prompt.
  prompt,
}

class EstudyanteGOApp extends StatefulWidget {
  const EstudyanteGOApp({
    super.key,
    this.initialSidebarCollapsed = false,
    this.initialThemeMode = ThemeMode.dark,
    this.initialThemePreference,
    this.authService,
    this.permissionService,
    this.notificationService,
  });

  final bool initialSidebarCollapsed;
  final ThemeMode initialThemeMode;

  /// Stored theme preference, when the caller read it (main() passes
  /// it). Null in tests that only inject an initial ThemeMode — the
  /// state then derives the preference from [initialThemeMode].
  final AppThemePreference? initialThemePreference;

  /// Auth backend. Null in tests that pump the app directly means
  /// "Firebase not configured" (gate falls back to the dashboard).
  final AuthService? authService;

  /// Notification permission backend. Null means the real
  /// permission_handler implementation.
  final PermissionService? permissionService;

  /// Local notification backend. Null means the real
  /// flutter_local_notifications implementation.
  final LocalNotificationService? notificationService;

  @override
  State<EstudyanteGOApp> createState() => _EstudyanteGOAppState();
}

class _EstudyanteGOAppState extends State<EstudyanteGOApp>
    with WidgetsBindingObserver {
  // The gate state sits above MaterialApp, so its own context has no
  // Navigator. Route pushes (profile setup) and dialogs (notification
  // prompt) go through this key instead.
  final _navigatorKey = GlobalKey<NavigatorState>();

  late ThemeMode _themeMode = widget.initialThemeMode;

  /// The stored theme preference behind [_themeMode]. Time Based is
  /// resolved to light/dark by the clock; the other options map
  /// straight onto their ThemeMode.
  late AppThemePreference _themePreference =
      widget.initialThemePreference ??
      appThemePreferenceForThemeMode(widget.initialThemeMode);

  /// Re-checks the Time Based theme once a minute while it is
  /// selected, so it flips at 6 AM / 6 PM without a restart. Null
  /// for the other options.
  Timer? _themeTimer;
  late final AuthService _authService =
      widget.authService ?? FirebaseAuthService(isConfigured: false);
  late final PermissionService _permissionService =
      widget.permissionService ?? AppPermissionService();

  /// Local notification service, created once per app: the real
  /// flutter_local_notifications implementation unless a test
  /// injects one.
  late final LocalNotificationService _notificationService =
      widget.notificationService ?? LocalNotificationService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startTimeBasedTimerIfNeeded();
    // Local notifications (Nov 8): initialize the plugin and build
    // the first schedule without awaiting — reminders must never
    // block the app start, and the service never throws.
    unawaited(_initLocalNotifications());
    // Home screen widgets (Nov 11): push the stored allowance /
    // fares / quotes / tasks into the widgets at startup,
    // and listen for widget taps (tap -> matching screen/tab).
    // Both are best-effort and never block startup.
    unawaited(AllowanceWidgetService.sync());
    unawaited(FaresWidgetService.sync());
    unawaited(DailyQuotesWidgetService.syncQuotes());
    unawaited(TasksWidgetService.sync());
    unawaited(_listenForWidgetClicks());
    localNotificationRefreshRequest.addListener(
      _onLocalNotificationRefreshRequested,
    );
    // Schedule home screen widgets (Nov 11): push the stored schedule
    // into the widgets at startup, and listen for widget taps (tap ->
    // Classes screen). Both are best-effort and never block startup.
    unawaited(ScheduleWidgetService.sync());
    unawaited(_listenForWidgetClicks());
  }

  Future<void> _initLocalNotifications() async {
    await _notificationService.initialize(onTap: _onNotificationTap);
    await _notificationService.refreshAll();
  }

  /// A notification was tapped (foreground tap, or the app was
  /// launched from a notification while closed): open the tab and
  /// Student-hub screen the payload points at
  /// ([notificationTargetForPayload]). A class / assignment / quiz
  /// tap opens Schedule; the route flag is consumed by the Student
  /// tab once the screen has been pushed.
  void _onNotificationTap(String? payload) {
    if (!mounted) return;
    final target = notificationTargetForPayload(payload);
    setState(() {
      _tabIndex = target.tab;
      _notificationRoute = target.screen;
    });
  }

  void _onLocalNotificationRefreshRequested() {
    unawaited(_notificationService.refreshAll());
  }

  // ---- Home screen widget taps (Nov 11) ----

  /// Listens for home screen widget taps: the stream while the app
  /// is alive, plus the launch URI when the app was started from a tap.
  Future<void> _listenForWidgetClicks() async {
    _widgetClickSubscription =
        HomeWidget.widgetClicked.listen(_onWidgetUri);
    final initial = await HomeWidget.initiallyLaunchedFromHomeWidget();
    if (initial != null) _onWidgetUri(initial);
  }

  /// A home screen widget tap: open the matching screen/tab when
  /// the dashboard is showing, otherwise hold the tap until it is.
  void _onWidgetUri(Uri? uri) {
    if (uri == null || !_isWidgetUri(uri.toString())) return;
    if (_destination == AppStartDestination.dashboard) {
      _openWidgetUriNow(uri);
    } else {
      _pendingWidgetUri = uri;
    }
  }

  bool _isWidgetUri(String uri) =>
      uri == ScheduleWidgetService.classesUri ||
      uri == AllowanceWidgetService.allowanceUri ||
      uri == FaresWidgetService.faresUri ||
      uri == DailyQuotesWidgetService.quotesUri ||
      uri == TasksWidgetService.tasksUri;

  /// Opens the matching screen/tab for a held widget tap, once the
  /// dashboard is showing. No-op when there is no held tap, or when
  /// the destination is not the dashboard yet.
  void _openWidgetUriIfPending() {
    if (_pendingWidgetUri == null ||
        _destination != AppStartDestination.dashboard) {
      return;
    }
    final uri = _pendingWidgetUri!;
    _pendingWidgetUri = null;
    _openWidgetUriNow(uri);
  }

  /// Dispatches a widget URI to its screen/tab. Pushed screens go
  /// through [_openWidgetScreen] (once-only per URI); the Fares tab
  /// switches tabs (popping any pushed screen first so the tab is
  /// visible).
  void _openWidgetUriNow(Uri uri) {
    final raw = uri.toString();
    if (raw == ScheduleWidgetService.classesUri) {
      _openWidgetScreen(
        raw,
        () => const StudentTheme(child: ClassesScreen()),
      );
      return;
    }
    if (raw == FaresWidgetService.faresUri) {
      _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      _selectTab(2);
      return;
    }
    if (raw == AllowanceWidgetService.allowanceUri) {
      _openWidgetScreen(
        raw,
        () => const StudentTheme(child: AllowanceScreen()),
      );
      return;
    }
    if (raw == DailyQuotesWidgetService.quotesUri) {
      _openWidgetScreen(
        raw,
        () => const StudentTheme(child: QuotesScreen()),
      );
      return;
    }
    if (raw == TasksWidgetService.tasksUri) {
      _openWidgetScreen(
        raw,
        () => const StudentTheme(child: ClassesScreen()),
      );
    }
  }

  /// Pushes a widget-opened screen on the app navigator, once, the
  /// same way the Student hub opens its screens (wrapped in
  /// StudentTheme). The push is deferred a frame so the dashboard
  /// is built first when the tap arrived during the gate.
  void _openWidgetScreen(String uri, Widget Function() builder) {
    if (_widgetScreensOpen.contains(uri)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _widgetScreensOpen.contains(uri)) return;
      final navigator = _navigatorKey.currentState;
      if (navigator == null) return;
      _widgetScreensOpen.add(uri);
      unawaited(
        navigator
            .push(MaterialPageRoute(builder: (_) => builder()))
            .whenComplete(() => _widgetScreensOpen.remove(uri)),
      );
    });
  }

  @override
  void dispose() {
    _themeTimer?.cancel();
    _widgetClickSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    localNotificationRefreshRequest.removeListener(
      _onLocalNotificationRefreshRequested,
    );
    super.dispose();
  }

  // ---- First-time gate state ----
  AppStartDestination? _destination;

  /// Home screen widget tap (Nov 11): the `homewidget://...` URI
  /// a widget sends, held until the dashboard is showing — a
  /// widget can be tapped while the app is still on the splash /
  /// auth / setup gate (see [_onWidgetUri]).
  Uri? _pendingWidgetUri;

  /// URIs of widget-opened screens currently on top, so a second
  /// tap cannot stack another copy of the same screen.
  final Set<String> _widgetScreensOpen = {};

  /// Stream subscription for widget taps while the app is alive.
  StreamSubscription<Uri?>? _widgetClickSubscription;

  /// True when an auth screen was reached from onboarding (the
  /// first-launch path). Only then does auth get a back button, and
  /// it returns to the welcome state (onboarding page 4). Every other
  /// path into auth (sign-out, verify escape hatch, fallbacks)
  /// has no back target, so no back button is shown there.
  bool _cameFromOnboarding = false;
  int _onboardingInitialPage = 0;
  AuthUser? _user;
  UserProfile? _profile;
  ProfileStore? _store;
  int _tabIndex = 0;

  /// Student-hub screen a tapped notification asked to open
  /// ('classes', 'bible' or 'allowance'; null = tab only). Set by
  /// [_onNotificationTap], consumed by the Student tab.
  String? _notificationRoute;

  /// Post-setup celebration phase (Feature 2). After a NEW user
  /// taps "Finish setup" on Profile Setup (step 8), the gate shows
  /// the celebration overlay, then the "You know how to use the
  /// app?" prompt, and only then the dashboard (step 9, Student
  /// tab). [none] is the normal state: no overlay up. Edit-profile
  /// saves (Account -> Edit profile) never touch this — they pop
  /// back via [_openProfileSetup] instead of the gate.
  _PostSetupPhase _postSetupPhase = _PostSetupPhase.none;

  /// TOUR HOOK (Feature 3 reads this — see [StudentTab.startWatchTour]).
  /// True only when the new user answered "No, show me how" on the
  /// post-setup prompt: the dashboard then lands on the Student tab
  /// with the Watch demo guided tour auto-started. Cleared when the
  /// tour starts (via [StudentTab.onWatchTourConsumed]) or on
  /// sign-out, so it never re-fires on a later visit.
  bool _startWatchTour = false;

  /// WELCOME BACK (Feature 4). True while a sign-in that originated
  /// on the Sign In page is still resolving (verified / profile
  /// restored) and has not landed yet. Only [_afterSignIn] sets it
  /// — the Create Account Google sign-up path (which also routes
  /// through [_afterAuth]) never does, so a new user never sees the
  /// Welcome Back overlay. Consumed by [_landOnDashboard]; cleared
  /// whenever the flow diverts to Profile Setup, on sign-out, and
  /// on "Use a different account".
  bool _welcomeBackPending = false;

  /// WELCOME BACK (Feature 4). True while the Welcome Back overlay
  /// is up over the dashboard destination (after a returning user
  /// signed in). Cleared by [_finishWelcomeBack] when the overlay
  /// ends (auto-advance or tap); the dashboard underneath is the
  /// Student tab. Never set by the new-user path.
  bool _showWelcomeBack = false;

  /// STUDENT ENTRANCE (Feature 5). True only when the Welcome
  /// Back overlay has just finished, so the Student tab plays its
  /// game-style entrance once on landing. Set by
  /// [_finishWelcomeBack] (the same moment the overlay ends) and
  /// consumed by the Student tab via [StudentTab.onEntranceConsumed]
  /// when the entrance starts (or is skipped) — never set by any
  /// other path, never re-armed by tab switches.
  bool _playStudentEntrance = false;

  /// Remote student-profile store, behind the same `isConfigured`
  /// gate as the shared-posts repository: null when Firebase is not
  /// configured, so the gate never touches Firestore on unconfigured
  /// builds (and widget tests pumping the app without a service keep
  /// the legacy local-only behavior).
  StudentProfileRepository? get _profileRepository =>
      _authService.isConfigured ? FirestoreStudentProfileRepository() : null;

  /// Login Alerts + Session Manager (Account → Security). Created
  /// once during [_resolveStart] (the splash always runs before
  /// any auth screen can appear) with the same `isConfigured`
  /// gate: no repository when Firebase is not configured, in which
  /// case the service records nothing and sign-in works as before.
  SessionService? _sessionService;

  SessionService _ensureSessionService(SharedPreferences prefs) {
    final existing = _sessionService;
    if (existing != null) return existing;
    final service = SessionService(
      prefs: prefs,
      repository: _authService.isConfigured
          ? FirestoreSessionRepository()
          : null,
      notify: ({required String title, required String body}) async {
        await _notificationService.showLoginAlert(
          title: title,
          body: body,
        );
      },
    );
    service.onForeignSession = _onForeignSession;
    service.onRevoked = _onSessionRevoked;
    _sessionService = service;
    return service;
  }

  /// A sign-in from another device was detected. The service
  /// already fired the local notification; the dialog asks 'Was
  /// this you?' — but only while the dashboard is showing, so it
  /// never pops over sign-in / setup. Otherwise the session stays
  /// visible in the Security Center for later.
  Future<void> _onForeignSession(UserSession session) async {
    final user = _user;
    if (user == null || _destination != AppStartDestination.dashboard) {
      return;
    }
    final context = _navigatorKey.currentContext;
    if (context == null || !mounted) return;
    final choice = await showLoginAlertDialog(
      context: context,
      session: session,
    );
    if (choice == null || !mounted) return;
    final service = _sessionService;
    if (service == null) return;
    if (choice == LoginAlertChoice.yesThatWasMe) {
      await service.markSessionTrusted(session);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Thanks — this sign-in is marked as trusted.',
          ),
        ),
      );
      return;
    }
    // 'No, secure my account': revoke the other session, flag the
    // account for a password change, and send the reset link
    // through the app's existing password-reset flow.
    await service.secureAccount(foreignSession: session, uid: user.uid);
    if (!context.mounted) return;
    try {
      await _authService.sendPasswordReset(email: user.email);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Other session signed out. Password reset link sent — '
            'check your email.',
          ),
        ),
      );
    } on AuthException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
    }
  }

  /// This device's session record was deleted from another device
  /// (mid-session revocation): sign out of Firebase and route to
  /// sign-in. No-op when already signed out.
  void _onSessionRevoked() {
    if (_user == null || !mounted) return;
    unawaited(_authService.signOut().catchError((_) {}));
    _signOut();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _navigatorKey.currentContext;
      if (context != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You were signed out from another device.'),
          ),
        );
      }
    });
  }

  /// Restores the server-side student profile into the local store
  /// (merge, backfill, or local-only fallback — never throws, never
  /// blocks login) and refreshes [_profile] from the local store so
  /// the dashboard and the setup screen both see restored data.
  Future<void> _restoreProfileForUser(AuthUser user) async {
    final store = _store ?? ProfileStore(await SharedPreferences.getInstance());
    _store = store;
    await restoreStudentProfile(
      store: store,
      repository: _profileRepository,
      user: user,
    );
    _profile = store.loadProfile(user.uid);
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    // Entry screens only ever flip light <-> dark explicitly (their
    // sun/moon toggle); map the explicit mode onto the matching
    // preference so the stored value and the Settings dialog stay
    // in sync.
    await _setThemePreference(appThemePreferenceForThemeMode(mode));
  }

  /// Applies a theme preference from Settings → General → Appearance:
  /// resolves it against the clock, persists the preference name
  /// ('system' / 'light' / 'dark' / 'timeBased') under the existing
  /// key, and (re)starts the Time Based re-check timer as needed.
  Future<void> _setThemePreference(AppThemePreference preference) async {
    setState(() {
      _themePreference = preference;
      _themeMode = resolveThemeMode(preference, DateTime.now());
    });
    _startTimeBasedTimerIfNeeded();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, preference.name);
    } catch (_) {
      // Theme already switched in memory; a failed local save is not fatal.
    }
  }

  /// Starts the once-a-minute Time Based re-check while Time Based is
  /// selected; stops it for the other options. The check itself is
  /// cheap (a DateTime read) and only rebuilds when the resolved mode
  /// actually changed.
  void _startTimeBasedTimerIfNeeded() {
    _themeTimer?.cancel();
    _themeTimer = null;
    if (_themePreference != AppThemePreference.timeBased) return;
    _themeTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => _refreshTimeBasedTheme(),
    );
  }

  /// Re-resolves the Time Based theme against the clock. No-op unless
  /// Time Based is selected, and only rebuilds when the resolved mode
  /// actually changed.
  void _refreshTimeBasedTheme() {
    if (_themePreference != AppThemePreference.timeBased) return;
    final resolved = resolveThemeMode(_themePreference, DateTime.now());
    if (resolved != _themeMode && mounted) {
      setState(() => _themeMode = resolved);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-evaluate the Time Based theme when the app comes back, so a
    // 6 AM / 6 PM flip that happened while it was backgrounded
    // applies immediately instead of waiting for the next tick.
    if (state == AppLifecycleState.resumed) {
      _refreshTimeBasedTheme();
      // Session heartbeat: refreshes last-active (throttled to one
      // write per 5 minutes inside the service).
      unawaited(_sessionService?.touchSession() ?? Future.value());
    }
  }

  void _selectTab(int index) {
    if (_tabIndex == index) return;
    setState(() => _tabIndex = index);
  }

  /// Runs while the splash shows: reads the stored flags and the
  /// current Firebase session, restores the server-side profile
  /// (the splash covers the fetch — never an empty setup screen
  /// while a fetch is pending), then decides the next screen.
  Future<AppStartDestination> _resolveStart() async {
    final prefs = await SharedPreferences.getInstance();
    final store = ProfileStore(prefs);
    final user = _authService.currentUser;
    _store = store;
    _user = user;
    // Auth session restore stage (the read itself is guarded inside
    // FirebaseAuthService.currentUser and returns null on failure).
    try {
      await ErrorLogService.instance.record(
        category: ErrorCategory.startup,
        message: user == null
            ? 'Auth session restore: no session.'
            : 'Auth session restore: session present.',
        startupStage: StartupStage.authSessionRestore.name,
        severity: ErrorSeverity.info,
      );
    } catch (_) {
      // Diagnostics failure must never break start resolution.
    }
    if (user != null) {
      // Session restore stage: re-adopt (or create) this device's
      // session record, and detect a revocation from another
      // device. A revoked device signs out here, before any
      // profile restore — the gate then routes to sign-in.
      //
      // The session feature must NEVER break or stall app start:
      // Firestore can be unreachable (or unmocked in tests), and a
      // hung write would leave the splash up forever. Bound it to
      // 10 s and fall through to normal start on any failure.
      var revoked = false;
      try {
        final service = _ensureSessionService(prefs);
        revoked = await service.onRestoredSession(user).timeout(
              const Duration(seconds: 10),
              onTimeout: () => false,
            );
      } catch (_) {
        revoked = false;
      }
      if (revoked) {
        try {
          await _authService.signOut();
        } catch (_) {}
        _user = null;
        _profile = null;
        return AppStartDestination.signIn;
      }
    }
    if (user != null) {
      // Profile restore stage: timeout + fallback to the local
      // profile. _restoreProfileForUser itself never throws by
      // contract; the wrapper adds timeout protection and a log
      // entry. It never clears session or onboarding progress.
      final diagnostics = ErrorLogService.instance.diagnostics;
      if (diagnostics != null) {
        await diagnostics.runStage<bool>(
          StartupStage.profileRestore,
          () async {
            await _restoreProfileForUser(user);
            return true;
          },
          fallback: false,
          timeout: const Duration(seconds: 15),
        );
      } else {
        await _restoreProfileForUser(user);
      }
    }
    final profileDone = user == null
        ? false
        : store.isProfileSetupDone(user.uid);
    _profile = user == null ? null : store.loadProfile(user.uid);
    return resolveStartDestination(
      firebaseConfigured: _authService.isConfigured,
      onboardingDone: store.onboardingDone,
      user: user,
      profileSetupDone: profileDone,
    );
  }

  Future<void> _markOnboardingDone() async {
    final store = _store ?? ProfileStore(await SharedPreferences.getInstance());
    _store = store;
    await store.markOnboardingDone();
  }

  void _goDashboard({bool promptForNotifications = false}) {
    unawaited(
      ErrorLogService.instance.record(
        category: ErrorCategory.startup,
        message: 'Dashboard init: destination set to dashboard.',
        startupStage: StartupStage.dashboardInit.name,
        severity: ErrorSeverity.info,
      ),
    );
    setState(() => _destination = AppStartDestination.dashboard);
    _openWidgetUriIfPending();
    if (promptForNotifications) _maybePromptForNotifications();
    // Reply notifications (Smart Notifications v1): an unread admin
    // reply in Chat Support or App Reviews fires one local
    // notification. Checked on dashboard arrival — there is no push
    // server, so this is the only delivery path.
    final user = _user;
    if (user != null) {
      unawaited(_notificationService.checkReplyNotifications(uid: user.uid));
    }
  }

  /// Shows the one-time notification-permission prompt on first
  /// authenticated arrival. The flag is set before the dialog so it
  /// never repeats, whatever the user chooses. Split out of
  /// [_goDashboard] so the Welcome Back overlay can defer it until
  /// the overlay ends instead of letting it pop over the overlay.
  void _maybePromptForNotifications() {
    if (_user == null || _store == null) return;
    final store = _store!;
    if (store.notificationPromptShown) return;
    // Show once, right after first authenticated arrival. The flag
    // is set before the dialog so it never repeats, whatever the
    // user chooses.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await store.markNotificationPromptShown();
      if (!mounted) return;
      final promptContext = _navigatorKey.currentContext;
      if (promptContext == null) return;
      await showNotificationPermissionPrompt(promptContext, _permissionService);
    });
  }

  /// End of the post-setup flow (Feature 2): the user answered the
  /// "You know how to use the app?" prompt. Both answers land on
  /// the Student tab (step 9); [startTour] (the "No, show me how"
  /// answer) additionally arms the Watch demo tour hook — see
  /// [_startWatchTour] and [StudentTab.startWatchTour]. The
  /// notification prompt still runs on first arrival, as before.
  void _finishSetupFlow({required bool startTour}) {
    setState(() {
      _postSetupPhase = _PostSetupPhase.none;
      _startWatchTour = startTour;
      _tabIndex = 0;
    });
    _goDashboard(promptForNotifications: true);
  }

  /// Sign In page success (Feature 4): the sign-in originated on
  /// the Sign In page (step 7 — email/password or login-only
  /// Google), from the onboarding gate, the Account-tab sign-in
  /// request, or a verify-email fallback. Arms the Welcome Back
  /// overlay for the dashboard landing; the shared [_afterAuth]
  /// below decides whether the landing actually happens (verified
  /// + profile complete) or diverts to Verify Email / Profile
  /// Setup instead. The Create Account Google sign-up path calls
  /// [_afterAuth] directly and never arms this, so a new user
  /// never sees the overlay.
  Future<void> _afterSignIn(AuthUser user) async {
    _welcomeBackPending = true;
    await _afterAuth(user);
  }

  Future<void> _afterAuth(AuthUser user) async {
    _user = user;
    final store = _store ?? ProfileStore(await SharedPreferences.getInstance());
    _store = store;
    if (!user.emailVerified) {
      // Keep [_welcomeBackPending]: the user signed in on the Sign
      // In page and will come back through [_afterVerified] once
      // the email is verified.
      setState(() => _destination = AppStartDestination.verifyEmail);
      return;
    }
    // Restore first so the setup screen (when shown) is prefilled
    // with saved fields, and a complete restored profile goes
    // straight to the dashboard instead of setup.
    await _restoreProfileForUser(user);
    if (!store.isProfileSetupDone(user.uid)) {
      // Incomplete profile: no Welcome Back overlay — this user
      // goes to Profile Setup, whose Finish has its own
      // celebration (Feature 2).
      _welcomeBackPending = false;
      setState(() {
        _postSetupPhase = _PostSetupPhase.none;
        _destination = AppStartDestination.profileSetup;
      });
      return;
    }
    _profile = store.loadProfile(user.uid);
    _landOnDashboard();
  }

  Future<void> _afterVerified(AuthUser user) async {
    _user = user;
    final store = _store ?? ProfileStore(await SharedPreferences.getInstance());
    _store = store;
    await _restoreProfileForUser(user);
    if (!store.isProfileSetupDone(user.uid)) {
      // Same as [_afterAuth]: an incomplete profile goes to setup
      // with its own celebration, never the Welcome Back overlay.
      _welcomeBackPending = false;
      setState(() {
        _postSetupPhase = _PostSetupPhase.none;
        _destination = AppStartDestination.profileSetup;
      });
      return;
    }
    _profile = store.loadProfile(user.uid);
    _landOnDashboard();
  }

  /// Dashboard landing shared by [_afterAuth] and [_afterVerified].
  /// When the landing follows a Sign In page success
  /// ([_welcomeBackPending]), the Welcome Back overlay shows first
  /// (Feature 4) and the notification prompt waits until it ends,
  /// so it never pops over the overlay. Otherwise the dashboard
  /// opens directly, as before. Either way the landing tab is the
  /// Student tab — the overlay never shows the "You know how to
  /// use the app?" prompt and never touches [_startWatchTour].
  void _landOnDashboard() {
    final showWelcomeBack = _welcomeBackPending;
    _welcomeBackPending = false;
    setState(() {
      _tabIndex = 0;
      _showWelcomeBack = showWelcomeBack;
    });
    _goDashboard(promptForNotifications: !showWelcomeBack);
  }

  /// End of the Welcome Back overlay (Feature 4): auto-advance or
  /// tap. The dashboard underneath is already the Student tab; the
  /// deferred first-arrival notification prompt runs now. Feature
  /// 5: the overlay finishing arms the Student tab entrance
  /// ([_playStudentEntrance]) — the tab plays it once on landing
  /// and consumes the flag, so no other arrival replays it.
  void _finishWelcomeBack() {
    setState(() {
      _showWelcomeBack = false;
      _playStudentEntrance = true;
    });
    _maybePromptForNotifications();
  }

  void _openProfileSetup({bool isEdit = false}) {
    final user = _user;
    final store = _store;
    final navigator = _navigatorKey.currentState;
    if (user == null || store == null || navigator == null) return;
    navigator.push(
      MaterialPageRoute(
        builder: (_) => ProfileSetupScreen(
          user: user,
          store: store,
          profileRepository: _profileRepository,
          initial: _profile,
          isEdit: isEdit,
          onSaved: (profile) {
            setState(() => _profile = profile);
            navigator.pop();
          },
        ),
      ),
    );
  }

  void _signOut() {
    // The session watchers stop here; the session record itself
    // was already deleted by the Account tab's sign-out (which
    // deletes the record while still signed in, then signs out of
    // Firebase). A sign-out that bypasses the tab (verify-email
    // escape hatch) leaves the record until the next start, when
    // the restored-session check re-adopts it.
    unawaited(_sessionService?.stopWatchers() ?? Future.value());
    setState(() {
      _user = null;
      _profile = null;
      _cameFromOnboarding = false;
      _postSetupPhase = _PostSetupPhase.none;
      _startWatchTour = false;
      _welcomeBackPending = false;
      _showWelcomeBack = false;
      _playStudentEntrance = false;
      _destination = _authService.isConfigured
          ? AppStartDestination.signIn
          : AppStartDestination.dashboard;
    });
  }

  /// Auth back button (first-launch path only): return to the welcome
  /// state (onboarding page 4), not to the start of the tour.
  void _backToOnboarding() {
    setState(() {
      _onboardingInitialPage = 3;
      _destination = AppStartDestination.onboarding;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EstudyanteGO',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      theme: _lightTheme(),
      darkTheme: _darkTheme(),
      themeMode: _themeMode,
      // flutter_quill throws without its delegate (Nov 8); the
      // Global* delegates are the MaterialApp defaults, restated
      // here because specifying localizationsDelegates replaces them.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      home: _gateWidget(),
    );
  }

  Widget _gateWidget() {
    final destination = _destination;
    if (destination == null) {
      return SplashScreen(
        resolve: _resolveStart,
        onDestination: (next) {
          setState(() => _destination = next);
    _openWidgetUriIfPending();
        },
        themeMode: _themeMode,
      );
    }
    switch (destination) {
      case AppStartDestination.onboarding:
        return OnboardingScreen(
          onGetStarted: () async {
            await _markOnboardingDone();
            if (!mounted) return;
            setState(() {
              _cameFromOnboarding = true;
              _destination = AppStartDestination.createAccount;
            });
          },
          onSignIn: () async {
            await _markOnboardingDone();
            if (!mounted) return;
            setState(() {
              _cameFromOnboarding = true;
              _destination = AppStartDestination.signIn;
            });
          },
          themeMode: _themeMode,
          onThemeModeChanged: _setThemeMode,
          initialPage: _onboardingInitialPage,
        );
      case AppStartDestination.signIn:
        return SignInScreen(
          service: _authService,
          onSignedIn: _afterSignIn,
          onCreateAccountRequested: () =>
              setState(() => _destination = AppStartDestination.createAccount),
          profileRepository: _profileRepository,
          sessionService: _sessionService,
          themeMode: _themeMode,
          onThemeModeChanged: _setThemeMode,
          onBack: _cameFromOnboarding ? _backToOnboarding : null,
        );
      case AppStartDestination.createAccount:
        return CreateAccountScreen(
          service: _authService,
          onAccountCreated: (user) {
            _user = user;
            setState(() => _destination = AppStartDestination.verifyEmail);
          },
          onSignedIn: _afterAuth,
          onSignInRequested: () =>
              setState(() => _destination = AppStartDestination.signIn),
          sessionService: _sessionService,
          themeMode: _themeMode,
          onThemeModeChanged: _setThemeMode,
          onBack: _cameFromOnboarding ? _backToOnboarding : null,
        );
      case AppStartDestination.verifyEmail:
        final user = _user;
        if (user == null) {
          // Should not happen (verify implies a user), but never trap
          // the user on a screen that needs one.
          return SignInScreen(
            service: _authService,
            onSignedIn: _afterSignIn,
            onCreateAccountRequested: () => setState(
              () => _destination = AppStartDestination.createAccount,
            ),
            profileRepository: _profileRepository,
            sessionService: _sessionService,
            themeMode: _themeMode,
            onThemeModeChanged: _setThemeMode,
          );
        }
        return VerifyEmailScreen(
          service: _authService,
          user: user,
          onVerified: _afterVerified,
          onUseDifferentAccount: () {
            setState(() {
              _user = null;
              _profile = null;
              _cameFromOnboarding = false;
              _welcomeBackPending = false;
              _showWelcomeBack = false;
              _destination = AppStartDestination.signIn;
            });
          },
        );
      case AppStartDestination.profileSetup:
        final user = _user;
        final store = _store;
        if (user == null || store == null) {
          return SignInScreen(
            service: _authService,
            onSignedIn: _afterSignIn,
            onCreateAccountRequested: () => setState(
              () => _destination = AppStartDestination.createAccount,
            ),
            profileRepository: _profileRepository,
            sessionService: _sessionService,
            themeMode: _themeMode,
            onThemeModeChanged: _setThemeMode,
          );
        }
        // Post-setup overlays (Feature 2): after "Finish setup"
        // the gate shows the celebration, then the guide prompt,
        // and only then the dashboard. The profile is already
        // saved by this point.
        if (_postSetupPhase == _PostSetupPhase.celebration) {
          return SetupCelebrationOverlay(
            onFinished: () =>
                setState(() => _postSetupPhase = _PostSetupPhase.prompt),
          );
        }
        if (_postSetupPhase == _PostSetupPhase.prompt) {
          return SetupGuidePromptOverlay(
            onTakeMeIn: () => _finishSetupFlow(startTour: false),
            onShowMeHow: () => _finishSetupFlow(startTour: true),
          );
        }
        return ProfileSetupScreen(
          user: user,
          store: store,
          profileRepository: _profileRepository,
          initial: _profile,
          onSaved: (profile) {
            _profile = profile;
            setState(() => _postSetupPhase = _PostSetupPhase.celebration);
          },
        );
      case AppStartDestination.dashboard:
        // WELCOME BACK (Feature 4): a returning user who just
        // signed in on the Sign In page sees this overlay first,
        // then the Student tab underneath. The photo uses the same
        // shared rule as the Student Hub / Account tab (local file
        // -> uploaded URL -> Google avatar); the first name comes
        // from the stored profile, then the Firebase display name.
        if (_showWelcomeBack) {
          final profile = _profile;
          final user = _user;
          return WelcomeBackOverlay(
            firstName: welcomeBackFirstName(profile: profile, user: user),
            displayName: profile?.displayName ?? user?.displayName,
            photoImage: resolveProfilePhoto(
              photoPath: profile?.photoPath,
              profilePhotoUrl: profile?.profilePhotoUrl,
              photoUrl: profile?.photoUrl ?? user?.photoUrl,
            ),
            onFinished: _finishWelcomeBack,
          );
        }
        return _HomeShell(
          initialSidebarCollapsed: widget.initialSidebarCollapsed,
          themePreference: _themePreference,
          onThemePreferenceChanged: _setThemePreference,
          selectedIndex: _tabIndex,
          onSelect: _selectTab,
          authService: _authService,
          user: _user,
          profile: _profile,
          // TOUR HOOK (Feature 3): "No, show me how" on the
          // post-setup prompt lands here with startWatchTour true.
          startWatchTour: _startWatchTour,
          onWatchTourConsumed: () => setState(() => _startWatchTour = false),
          // ENTRANCE HOOK (Feature 5): the Welcome Back overlay
          // just finished — the Student tab plays its game-style
          // entrance once on landing, then consumes the flag.
          playStudentEntrance: _playStudentEntrance,
          onStudentEntranceConsumed: () =>
              setState(() => _playStudentEntrance = false),
          // NOTIFICATION DEEP LINK (Smart Notifications v1): a
          // tapped notification opens this screen on the Student
          // tab; the tab consumes the flag once pushed.
          notificationRoute: _notificationRoute,
          onNotificationRouteConsumed: () =>
              setState(() => _notificationRoute = null),
          permissionService: _permissionService,
          notificationService: _notificationService,
          sessionService: _sessionService,
          onViewStudent: () => _selectTab(0),
          onViewCommunities: () => _selectTab(4),
          onViewFares: () => _selectTab(2),
          onViewMap: () => _selectTab(3),
          onEditProfile: () => _openProfileSetup(isEdit: true),
          onSignInRequested: () {
            setState(() {
              _destination = AppStartDestination.signIn;
            });
          },
          onSignedOut: _signOut,
        );
    }
  }
}

class _HomeShell extends StatefulWidget {
  const _HomeShell({
    required this.initialSidebarCollapsed,
    required this.themePreference,
    required this.onThemePreferenceChanged,
    required this.selectedIndex,
    required this.onSelect,
    required this.authService,
    required this.user,
    required this.profile,
    this.startWatchTour = false,
    this.onWatchTourConsumed,
    this.playStudentEntrance = false,
    this.onStudentEntranceConsumed,
    this.notificationRoute,
    this.onNotificationRouteConsumed,
    required this.permissionService,
    required this.notificationService,
    this.sessionService,
    required this.onViewStudent,
    required this.onViewCommunities,
    required this.onViewFares,
    required this.onViewMap,
    required this.onEditProfile,
    required this.onSignInRequested,
    required this.onSignedOut,
  });

  final bool initialSidebarCollapsed;
  final AppThemePreference themePreference;
  final ValueChanged<AppThemePreference> onThemePreferenceChanged;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final AuthService authService;
  final AuthUser? user;
  final UserProfile? profile;

  /// TOUR HOOK (Feature 3): true when the new user answered "No,
  /// show me how" on the post-setup prompt. Passed through to
  /// [StudentTab.startWatchTour]; see the contract there.
  final bool startWatchTour;

  /// TOUR HOOK (Feature 3): called once the tour starts, so the
  /// flag clears and never re-fires. Passed through to
  /// [StudentTab.onWatchTourConsumed].
  final VoidCallback? onWatchTourConsumed;

  /// ENTRANCE HOOK (Feature 5): true when the Welcome Back
  /// overlay just finished. Passed through to
  /// [StudentTab.playEntrance]; see the contract there.
  final bool playStudentEntrance;

  /// ENTRANCE HOOK (Feature 5): called once the entrance starts
  /// (or is skipped), so the flag clears and never re-fires.
  /// Passed through to [StudentTab.onEntranceConsumed].
  final VoidCallback? onStudentEntranceConsumed;

  /// NOTIFICATION DEEP LINK (Smart Notifications v1): the
  /// Student-hub screen a tapped notification asked to open
  /// ('classes', 'bible' or 'allowance'; null = tab only). Passed
  /// through to [StudentTab.notificationRoute].
  final String? notificationRoute;

  /// NOTIFICATION DEEP LINK: called once the tab has pushed the
  /// screen (or decided there is none), so the flag clears and
  /// never re-fires. Passed through to
  /// [StudentTab.onNotificationRouteConsumed].
  final VoidCallback? onNotificationRouteConsumed;

  final PermissionService permissionService;
  final LocalNotificationService notificationService;

  /// Login Alerts + Session Manager (Account → Security). Null in
  /// tests and when Firebase is not configured — the Account tab
  /// then keeps its previous behavior (no Security Center row).
  final SessionService? sessionService;
  final VoidCallback onViewStudent;
  final VoidCallback onViewCommunities;
  final VoidCallback onViewFares;
  final VoidCallback onViewMap;
  final VoidCallback onEditProfile;
  final VoidCallback onSignInRequested;
  final VoidCallback onSignedOut;

  @override
  State<_HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<_HomeShell>
    with SingleTickerProviderStateMixin {
  late bool _collapsed = widget.initialSidebarCollapsed;

  /// Tab-switch fade-slide (preview animation pass, Nov 6): the
  /// controller restarts on every tab change (didUpdateWidget) —
  /// the IndexedStack itself is never rebuilt or re-keyed, so tab
  /// state (scroll, input, the Map's active route) survives the
  /// switch. Fast/subtle (180ms); reduced motion = instant.
  late final AnimationController _tabFadeController;
  late final Animation<double> _tabFadeProgress;

  /// Shared wallet state, created once per shell: the real Firestore
  /// backend when Firebase is configured, local-only mode otherwise
  /// (widget tests keep the legacy 0-balance display). Passed to
  /// the Student and Account tabs so a sign-in claim updates the
  /// Account UI immediately.
  late final PointsWalletController _walletController = PointsWalletController(
    repository: widget.authService.isConfigured
        ? FirestorePointsWalletRepository()
        : null,
  );

  /// Shared credits state (Queue #2), created once per shell with
  /// the same configured/local-only split. Passed to the Student
  /// and Account tabs so a redemption updates both immediately.
  late final CreditsController _creditsController = CreditsController(
    repository: widget.authService.isConfigured
        ? FirestoreCreditsRepository()
        : null,
  );

  /// Shared AdMob state (ads phase), created once per shell.
  /// Initialized in initState without awaiting: ads must never
  /// block the shell, and the service never throws.
  late final AdService _adService = GoogleMobileAdsService();

  /// Watch demo tour (Feature 3): one controller per shell, passed
  /// to the Student tab (which registers its cards) and rendered
  /// as an overlay above the whole shell below, so stop 1 can
  /// highlight the top nav (phone) / left sidebar (tablet) — both
  /// registered here under the same 'nav' stop id; only the one
  /// actually laid out is used.
  late final WatchTourController _tourController = WatchTourController();
  final _topNavKey = GlobalKey();
  final _sidebarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _tourController.registerTarget('nav', _topNavKey);
    _tourController.registerTarget('nav', _sidebarKey);
    _tabFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _tabFadeProgress = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _tabFadeController, curve: Curves.easeOut),
    );
    // No entrance animation on first launch — only on switches.
    _tabFadeController.value = 1;
    // Safe Mode skips ads init (nonessential). Otherwise the
    // existing fire-and-forget init is unchanged.
    if (ErrorLogService.instance.safeMode) {
      unawaited(
        ErrorLogService.instance.record(
          category: ErrorCategory.startup,
          message: 'Ads init skipped (Safe Mode).',
          startupStage: 'adsInit',
          severity: ErrorSeverity.warning,
        ),
      );
    } else {
      unawaited(_adService.initialize());
    }
  }

  @override
  void didUpdateWidget(covariant _HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      if (MediaQuery.of(context).disableAnimations) {
        _tabFadeController.value = 1;
      } else {
        _tabFadeController.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _tabFadeController.dispose();
    _tourController.dispose();
    super.dispose();
  }

  Future<void> _toggleSidebar() async {
    setState(() => _collapsed = !_collapsed);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_sidebarCollapsedKey, _collapsed);
    } catch (_) {
      // Sidebar already toggled in memory; a failed local save is not fatal.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Phones: wordmark header + icon-only top nav (no bottom nav).
    // Tablets / wide screens: collapsible left sidebar (unchanged).
    // One codebase, both form factors. The IndexedStack order
    // follows _destinations: Student, Study, Fares, Map,
    // Communities, Account — Student (index 0) is the default tab.
    final wide = MediaQuery.sizeOf(context).width >= 600;
    final body = IndexedStack(
      index: widget.selectedIndex,
      children: [
        StudentHubTheme(
          child: StudentTab(
            onViewOnMap: () => widget.onSelect(3),
            onViewAccount: () => widget.onSelect(5),
            user: widget.user,
            profile: widget.profile,
            // TOUR HOOK (Feature 3): forwarded verbatim from the
            // gate; see [StudentTab.startWatchTour].
            startWatchTour: widget.startWatchTour,
            onWatchTourConsumed: widget.onWatchTourConsumed,
            // ENTRANCE HOOK (Feature 5): forwarded verbatim from
            // the gate; see [StudentTab.playEntrance]. Only the
            // Welcome Back finish arms it.
            playEntrance: widget.playStudentEntrance,
            onEntranceConsumed: widget.onStudentEntranceConsumed,
            // NOTIFICATION DEEP LINK (Smart Notifications v1):
            // forwarded verbatim from the gate; see
            // [StudentTab.notificationRoute].
            notificationRoute: widget.notificationRoute,
            onNotificationRouteConsumed:
                widget.onNotificationRouteConsumed,
            // Watch demo tour (Feature 3): the shell's controller
            // — the tab registers its cards on it, and the shell
            // renders the overlay above the whole shell.
            tourController: _tourController,
            walletController: _walletController,
            creditsController: _creditsController,
            adService: _adService,
            // Admin-reply notifications (Nov 9, 2026): cloud repo
            // only when Firebase is configured; otherwise the
            // Notifications sheet keeps its empty state and the
            // bell shows no badge.
            reviewNotificationRepository: widget.authService.isConfigured
                ? FirestoreAppReviewNotificationRepository()
                : null,
          ),
        ),
        StudyTab(
          walletController: _walletController,
          visible: widget.selectedIndex == 1,
          currentUser: widget.user,
          // Files storage limit + enforcement: the shell's loaded
          // local profile carries the admin-assigned plan
          // (ProfileStore.loadProfile); the tab never writes it.
          plan: widget.profile?.plan ?? SubscriptionPlanId.free,
          // File sharing (Nov 8): cloud friends only when Firebase
          // is configured; shared-file storage follows the same
          // Firestore-vs-Local choice as the Fares tab repos.
          friendCloudRepository: widget.authService.isConfigured
              ? FirestoreFriendCloudRepository()
              : null,
          sharedFileRepository: widget.authService.isConfigured
              ? FirestoreSharedStudyFileRepository()
              : LocalSharedStudyFileRepository(),
        ),
        FaresTab(
          onViewOnMap: () => widget.onSelect(3),
          currentUser: widget.user,
          customRouteRepository: widget.authService.isConfigured
              ? FirestoreCustomRouteRepository()
              : LocalCustomRouteRepository(),
          fareOverrideRepository: widget.authService.isConfigured
              ? FirestoreRouteFareOverrideRepository()
              : LocalRouteFareOverrideRepository(),
          hiddenRouteRepository: widget.authService.isConfigured
              ? FirestoreHiddenRouteRepository()
              : LocalHiddenRouteRepository(),
          busStopRepository: widget.authService.isConfigured
              ? FirestoreBusStopRepository()
              : LocalBusStopRepository(),
          busCompanyRepository: widget.authService.isConfigured
              ? FirestoreBusCompanyRepository()
              : LocalBusCompanyRepository(),
        ),
        MapTab(
          currentUser: widget.user,
          visible: widget.selectedIndex == 3,
          customRouteRepository: widget.authService.isConfigured
              ? FirestoreCustomRouteRepository()
              : LocalCustomRouteRepository(),
          fareOverrideRepository: widget.authService.isConfigured
              ? FirestoreRouteFareOverrideRepository()
              : LocalRouteFareOverrideRepository(),
          busStopRepository: widget.authService.isConfigured
              ? FirestoreBusStopRepository()
              : LocalBusStopRepository(),
        ),
        CommunitiesTab(
          onViewOnMap: () => widget.onSelect(3),
          currentUser: widget.user,
          postRepository: widget.authService.isConfigured
              ? FirestorePostRepository()
              : null,
        ),
        AccountTab(
          themePreference: widget.themePreference,
          onThemePreferenceChanged: widget.onThemePreferenceChanged,
          authService: widget.authService,
          user: widget.user,
          profile: widget.profile,
          permissionService: widget.permissionService,
          notificationService: widget.notificationService,
          sessionService: widget.sessionService,
          walletController: _walletController,
          creditsController: _creditsController,
          adService: _adService,
          // About screen's live stats graph (Nov 8): same
          // Firestore-vs-Local choice as the Fares tab.
          customRouteRepository: widget.authService.isConfigured
              ? FirestoreCustomRouteRepository()
              : LocalCustomRouteRepository(),
          onViewStudent: widget.onViewStudent,
          onViewCommunities: widget.onViewCommunities,
          onViewFares: widget.onViewFares,
          onViewMap: widget.onViewMap,
          onEditProfile: widget.onEditProfile,
          onSignInRequested: widget.onSignInRequested,
          onSignedOut: widget.onSignedOut,
        ),
      ],
    );

    // Tab-switch fade-slide (preview animation pass, Nov 6): the
    // IndexedStack is the animation's `child`, so it is never
    // rebuilt on a switch — tab state is preserved.
    final animatedBody = AnimatedBuilder(
      animation: _tabFadeProgress,
      builder: (context, child) {
        final progress = _tabFadeProgress.value;
        return Opacity(
          opacity: 0.35 + 0.65 * progress,
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - progress)),
            child: child,
          ),
        );
      },
      child: body,
    );

    // Rating prompt (Nov 9): the floating pill + card + popup
    // overlay every tab — the overlay wraps the tab content once
    // and is used by both the wide and phone shells below. The
    // card header names the tab it floats over.
    final ratedBody = AppRatingOverlay(
      currentUserId: widget.user?.uid,
      currentTabLabel: _destinations[widget.selectedIndex].label,
      child: animatedBody,
    );

    // Admin-reply popup (Nov 9): when the admin replies to the
    // student's review while the app is open, a dark card pops up
    // at the top of the screen (same style as the rating flow's
    // "Thank you!" popup). The bell badge and the Notifications
    // sheet carry the reply persistently; the popup is the visible
    // alert. Same wrapping as the rating overlay above — one
    // instance, used by both shells.
    final replyBody = AppReplyPopupOverlay(
      repository: widget.authService.isConfigured
          ? FirestoreAppReviewNotificationRepository()
          : null,
      userId: widget.user?.uid,
      child: ratedBody,
    );

    // Support-reply popup (Nov 11, 2026): when Steven replies to
    // the student's Chat Support thread while the app is open, the
    // same dark top card pops up ("EstudyanteGO replied") and
    // tapping it opens Chat Support. Same wrapping as the review
    // reply overlay above — one instance, used by both shells.
    final supportBody = SupportReplyPopupOverlay(
      repository: widget.authService.isConfigured
          ? FirestoreSupportRepository()
          : null,
      userId: widget.user?.uid,
      onOpenChat: () {
        final user = widget.user;
        if (user == null) return;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ChatSupportScreen(
              repository: FirestoreSupportRepository(),
              user: user,
              studentName: supportFirstName(
                widget.profile?.displayName ?? user.displayName,
                user.email,
              ),
            ),
          ),
        );
      },
      child: replyBody,
    );

    // Watch demo tour (Feature 3): the overlay sits above the
    // whole shell — whichever branch below is built — so stop 1
    // can highlight the top nav (phone) / left sidebar (tablet).
    // When the tour is inactive the overlay is zero-size and the
    // shell below is untouched.
    final Widget shellScaffold = wide
        ? Scaffold(
            appBar: AppBar(
              title: Text(_destinations[widget.selectedIndex].label),
            ),
            // Top inset is handled by the AppBar; left/right/bottom insets
            // (gesture bar, cutouts) are respected here.
            body: SafeArea(
              top: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Sidebar(
                    key: _sidebarKey,
                    collapsed: _collapsed,
                    selectedIndex: widget.selectedIndex,
                    onSelect: widget.onSelect,
                    onToggle: _toggleSidebar,
                  ),
                  // Expanded content stays responsive while the sidebar
                  // animates; no overflow, no layout shift of the content.
                  Expanded(child: supportBody),
                ],
              ),
            ),
          )
        // Phones (preview port, Nov 6): the plain "EstudyanteGO"
        // wordmark header + the icon-only top nav directly under it.
        // There is NO bottom nav on phones anymore (the floating
        // glass capsule / iOS glass bar are retired); the top nav is
        // the only tab switcher. The wide branch above is untouched.
        : Scaffold(
            body: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _PhoneHeader(onBell: () => _showNotifications(context)),
                  TopNavBar(
                    key: _topNavKey,
                    selectedIndex: widget.selectedIndex,
                    onSelect: widget.onSelect,
                    destinations: [
                      for (final d in _destinations)
                        TopNavDestination(d.label, d.icon, d.selectedIcon),
                    ],
                  ),
                  Expanded(child: supportBody),
                ],
              ),
            ),
          );

    return Stack(
      children: [
        shellScaffold,
        WatchTourOverlay(controller: _tourController),
      ],
    );
  }

  /// Header bell: the app has no notification system, so this is
  /// the same honest empty state the Student tab bell shows — never
  /// a fake unread dot.
  void _showNotifications(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Padding(
        padding: AppLayout.pagePaddingLarge,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Notifications', style: AppText.headingStrong),
            SizedBox(height: AppSpacing.s8),
            Text('No notifications yet.'),
            SizedBox(height: AppSpacing.s4),
            Text(
              'Reminders you turn on in Notification Settings arrive '
              'as system notifications. There is no inbox here yet.',
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }
}

/// Phone header (Minecraft theme, Feature 1): grass gradient
/// (grass-bright → grass-mid) with a 4px grass-deep bottom border,
/// white Baloo 2 "EstudyanteGO" wordmark, dirt underline bar, and
/// the notifications bell. NO logo mark.
///
/// NOTE: there is deliberately NO theme toggle here. The preview's
/// header theme toggle is preview chrome; the Nov 5 rule keeps the
/// dark-mode toggle ONLY in Settings → General → Appearance, and
/// the real app keeps its existing theme handling.
class _PhoneHeader extends StatelessWidget {
  const _PhoneHeader({required this.onBell});

  final VoidCallback onBell;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: MinecraftDecorations.grassHeader,
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'EstudyanteGO',
                  style: MinecraftText.heading(
                    color: Colors.white,
                    fontSize: 22,
                  ).copyWith(letterSpacing: -0.5),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 48,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: MinecraftColors.dirtBrown,
                    border: Border(
                      bottom: BorderSide(
                        color: MinecraftColors.dirtDark,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Feature 6: the notification bell plays bell. The
          // wrapper only observes the pointer; the IconButton
          // still owns the tap.
          MinecraftTapAnimation(
            sound: MinecraftSoundKind.bell,
            child: IconButton(
              key: const Key('header-notifications'),
              icon: const Icon(
                Icons.notifications_outlined,
                color: Colors.white,
              ),
              tooltip: 'Notifications',
              onPressed: onBell,
            ),
          ),
        ],
      ),
    );
  }
}

/// Collapsible left sidebar for the wide layout.
///
/// Expanded (220dp): logo + "EstudyanteGO" name at the top, then icon + label
/// rows. Collapsed (80dp): icons only, centered, labels hidden, selected
/// indicator preserved, every icon wrapped in a Tooltip. The chevron
/// toggle sits at the very top. Width animates (~225ms, easeInOut);
/// collapsing never touches the selected tab.
///
/// Layout switch: the expanded rows need ~144dp, so while the width
/// animates the sidebar shows the collapsed layout below 150dp and the
/// expanded layout at/above it — that way no row ever overflows
/// mid-animation (a plain ClipRect only clips paint, not layout).
class _Sidebar extends StatefulWidget {
  const _Sidebar({
    super.key,
    required this.collapsed,
    required this.selectedIndex,
    required this.onSelect,
    required this.onToggle,
  });

  final bool collapsed;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onToggle;

  @override
  State<_Sidebar> createState() => _SidebarState();
}

class _SidebarState extends State<_Sidebar>
    with SingleTickerProviderStateMixin {
  static const double _expandedWidth = 220;
  static const double _collapsedWidth = 80;
  static const double _layoutSwitchWidth = 150;

  late final AnimationController _controller;
  late final Animation<double> _width;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 225),
      value: widget.collapsed ? 1 : 0,
    );
    _width = Tween<double>(
      begin: _expandedWidth,
      end: _collapsedWidth,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didUpdateWidget(covariant _Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.collapsed != oldWidget.collapsed) {
      if (widget.collapsed) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF94A3B8)
        : _textSecondary;
    return AnimatedBuilder(
      animation: _width,
      builder: (context, _) {
        final width = _width.value;
        final collapsedLayout = width < _layoutSwitchWidth;
        return SizedBox(
          key: const Key('sidebar-container'),
          width: width,
          child: ClipRect(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(
                  right: BorderSide(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? scheme.outline
                        : MinecraftColors.border,
                    width: 3,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (collapsedLayout)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Column(
                        children: [
                          IconButton(
                            key: const Key('sidebar-toggle'),
                            icon: const Icon(Icons.chevron_right),
                            tooltip: 'Expand sidebar',
                            onPressed: widget.onToggle,
                          ),
                          const SizedBox(height: 8),
                          const _LogoMark(),
                        ],
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          const _LogoMark(),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'EstudyanteGO',
                              overflow: TextOverflow.ellipsis,
                              style: MinecraftText.heading(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 18,
                              ),
                            ),
                          ),
                          IconButton(
                            key: const Key('sidebar-toggle'),
                            icon: const Icon(Icons.chevron_left),
                            tooltip: 'Collapse sidebar',
                            onPressed: widget.onToggle,
                          ),
                        ],
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int i = 0; i < _destinations.length; i++)
                            collapsedLayout
                                ? _collapsedItem(
                                    _destinations[i],
                                    i == widget.selectedIndex,
                                    muted,
                                    () => widget.onSelect(i),
                                  )
                                : _expandedItem(
                                    _destinations[i],
                                    i == widget.selectedIndex,
                                    muted,
                                    () => widget.onSelect(i),
                                  ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _expandedItem(
    _Destination destination,
    bool selected,
    Color muted,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        key: Key('sidebar-item-${destination.label}'),
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(MinecraftShapes.buttonRadius),
          onTap: onTap,
          // Feature 5: tap squash + ring/bits. The wrapper only
          // observes the pointer; the InkWell still owns the tap.
          // Feature 6: sidebar tabs play pop.
          child: MinecraftTapAnimation(
            sound: MinecraftSoundKind.pop,
            child: Container(
              height: 56,
              decoration: selected
                  ? BoxDecoration(
                      color: MinecraftColors.grassGreen,
                      borderRadius: BorderRadius.circular(
                        MinecraftShapes.buttonRadius,
                      ),
                      border: MinecraftShapes.buttonBorder,
                      boxShadow: const [MinecraftShapes.hardShadow],
                    )
                  : null,
              child: Row(
                children: [
                  const SizedBox(width: 12),
                  Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 24,
                    color: selected ? Colors.white : muted,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      destination.label,
                      overflow: TextOverflow.ellipsis,
                      style: MinecraftText.button(
                        color: selected ? Colors.white : muted,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _collapsedItem(
    _Destination destination,
    bool selected,
    Color muted,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Tooltip(
          message: destination.label,
          child: Material(
            key: Key('sidebar-item-${destination.label}'),
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(MinecraftShapes.buttonRadius),
              onTap: onTap,
              // Feature 5: tap squash + ring/bits. The wrapper
              // only observes the pointer; the InkWell still owns
              // the tap. Feature 6: sidebar tabs play pop.
              child: MinecraftTapAnimation(
                sound: MinecraftSoundKind.pop,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: selected
                      ? BoxDecoration(
                          color: MinecraftColors.grassGreen,
                          borderRadius: BorderRadius.circular(
                            MinecraftShapes.buttonRadius,
                          ),
                          border: MinecraftShapes.buttonBorder,
                        )
                      : null,
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    size: 24,
                    color: selected ? Colors.white : muted,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small branded mark: grass block (grass green, 3px ink border)
/// with a bus icon — the Minecraft logo block.
class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: MinecraftColors.grassGreen,
        borderRadius: BorderRadius.circular(10),
        border: MinecraftShapes.buttonBorder,
      ),
      child: const Icon(Icons.directions_bus, color: Colors.white, size: 22),
    );
  }
}
