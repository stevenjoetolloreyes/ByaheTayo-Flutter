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
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'features/diagnostics/diagnostics.dart';

import 'features/account_tab.dart';
import 'features/ad_service.dart';
import 'features/app_layout.dart';
import 'features/bus_companies.dart';
import 'features/bus_stops.dart';
import 'features/communities_tab.dart';
import 'features/community_post_repository.dart';
import 'features/credits_repository.dart';
import 'features/custom_routes.dart';
import 'features/fares_tab.dart';
import 'features/ios_components.dart';
import 'features/route_fare_overrides.dart';
import 'features/map_tab.dart';
import 'features/study_tab.dart';
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
import 'features/onboarding/splash_screen.dart';
import 'features/onboarding/verify_email_screen.dart';
import 'features/student_tab.dart';
import 'features/student/student_theme.dart';

/// SharedPreferences key for the sidebar collapsed state.
const _sidebarCollapsedKey = 'byahetayo_sidebar_collapsed';

/// SharedPreferences key for the theme mode ('system', 'light', 'dark').
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
        storage: FileErrorLogStorage(
          File('${docs.path}/error_logs.jsonl'),
        ),
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
          unawaited(diagnosticsService.record(
            category: ErrorCategory.startup,
            message: succeeded
                ? 'App Check activation succeeded.'
                : 'App Check activation did not complete '
                    '(best-effort; launch continues).',
            startupStage: StartupStage.appCheck.name,
            severity:
                succeeded ? ErrorSeverity.info : ErrorSeverity.warning,
          ));
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
          unawaited(diagnosticsService.record(
            category: ErrorCategory.startup,
            message: succeeded
                ? 'App Check activation succeeded.'
                : 'App Check activation did not complete '
                    '(best-effort; launch continues).',
            startupStage: StartupStage.appCheck.name,
            severity:
                succeeded ? ErrorSeverity.info : ErrorSeverity.warning,
          ));
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

  runZonedGuarded(
    () {
      runApp(
        EstudyanteGOApp(
          initialSidebarCollapsed:
              prefs?.getBool(_sidebarCollapsedKey) ?? false,
          initialThemeMode: _themeModeFromString(
            prefs?.getString(_themeModeKey),
          ),
          authService: FirebaseAuthService(isConfigured: firebaseConfigured),
        ),
      );
      unawaited(diagnosticsService.record(
        category: ErrorCategory.startup,
        message: 'runApp called.',
        severity: ErrorSeverity.info,
      ));
    },
    diagnosticsService.handleZoneError,
  );
}

ThemeMode _themeModeFromString(String? value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      // Preview default is DARK (Nov 7): no stored preference means
      // dark, not system. A stored 'light' / 'dark' / 'system' still
      // wins — the Settings → General → Appearance toggle is the
      // only thing that writes this key.
      return ThemeMode.dark;
  }
}

// ---- Brand — Premium Dark Minimalist redesign (Oct 31 spec): emerald accent ----
const _primary = Color(0xFF16A34A);
const _deepEmerald = Color(0xFF14532D);
const _primaryDark = Color(0xFF059669);
const _indicatorLight = Color(0xFFD1FAE5);
const _indicatorDark = Color(0xFF064E3B);
const _bgLight = Color(0xFFF1F5F9);
const _textDark = Color(0xFF0F172A);
const _textSecondary = Color(0xFF64748B);

// Preview tokens (Nov 7): the Fares Phone Preview's dark emerald UI
// — page background #0c1410, brand #16a34a, accent #34d399. The dark
// theme below is built from these; the light theme keeps its own
// approved values and only gains the preview fonts.
const _previewDarkBg = Color(0xFF0C1410);
const _previewDarkCard = Color(0xFF202B25);
const _previewDarkElevated = Color(0xFF252B2D);
const _previewAccent = Color(0xFF34D399);
const _previewDarkSubtext = Color(0xFFB0B8B5);
const _previewDarkBorder = Color(0xFF343B3D);

ThemeData _lightTheme() {
  final scheme = const ColorScheme.light(
    primary: _primary,
    onPrimary: Colors.white,
    secondary: _primaryDark,
    surface: Colors.white,
    onSurface: _textDark,
    outline: Color(0xFFE2E8F0),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: _bgLight,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: _textDark,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'PlusJakartaSans',
        color: _textDark,
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 0,
      indicatorColor: _indicatorLight,
      iconTheme: const WidgetStatePropertyAll(IconThemeData(size: AppLayout.navIconSize)),
      labelTextStyle: const WidgetStatePropertyAll(
        AppText.smallSemiBold,
      ),
    ),
    // Premium Dark Minimalist card language (shared by every tab, and
    // the same language the Map sheet already uses): 16dp corners,
    // a subtle outline, no elevation shadow.
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppLayout.cardRadius)),
        side: BorderSide(color: Color(0xFFE2E8F0)),
      ),
    ),
    // iOS-style component shaping (Nov 7): dialogs, sheets, fields
    // and buttons get the iOS look (large rounded corners, no
    // shadows, rounded filled fields) while keeping the app's
    // colors, fonts, and behaviour. Cupertino widgets themselves
    // get their theme from cupertinoOverrideTheme below.
    dialogTheme: const DialogThemeData(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.all(Radius.circular(AppLayout.dialogRadius)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      modalBackgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
      dragHandleColor: Color(0xFFCBD5E1),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: _primary, width: 1.5),
      ),
      hintStyle: TextStyle(color: _textSecondary),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineWidth: const WidgetStatePropertyAll(0),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? _primary
            : const Color(0xFFE2E8F0),
      ),
    ),
    // iOS-style components (Nov 7): Cupertino widgets read this
    // override (emerald + Inter) instead of the default iOS blue /
    // SF Pro. CupertinoTheme.of falls back to it when no CupertinoTheme
    // ancestor exists. (MaterialApp has no cupertinoOverrideTheme
    // parameter — it lives on ThemeData.)
    cupertinoOverrideTheme:
        iosCupertinoTheme(Brightness.light).noDefault(),
  );
}

ThemeData _darkTheme() {
  // Preview dark tokens (Nov 7): #0c1410 page, #202B25 cards,
  // #252B2D elevated, white primary text, #B0B8B5 secondary text,
  // #343B3D borders — the same surfaces the Student Hub, Fares and
  // Account tabs already use for dark mode. Brand #16a34a is the
  // primary (buttons, selected pills, brand surfaces) with white
  // text, exactly like the preview; accent #34d399 is the secondary
  // for bright text highlights on dark surfaces.
  final scheme = const ColorScheme.dark(
    primary: _primary,
    onPrimary: Colors.white,
    secondary: _previewAccent,
    onSecondary: Color(0xFF052E16),
    surface: _previewDarkCard,
    onSurface: Color(0xFFFFFFFF),
    surfaceContainerHighest: _previewDarkElevated,
    onSurfaceVariant: _previewDarkSubtext,
    outline: _previewDarkBorder,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: _previewDarkBg,
    appBarTheme: const AppBarTheme(
      backgroundColor: _previewDarkBg,
      foregroundColor: Color(0xFFFFFFFF),
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: 'PlusJakartaSans',
        color: Color(0xFFFFFFFF),
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: _previewDarkBg,
      elevation: 0,
      indicatorColor: _indicatorDark,
      iconTheme: WidgetStatePropertyAll(IconThemeData(size: AppLayout.navIconSize)),
      labelTextStyle: WidgetStatePropertyAll(
        AppText.smallSemiBold,
      ),
    ),
    // Dark card language: #202B25 surface, #343B3D outline, 16dp
    // corners, no shadow — same as the Student Hub / Fares dark cards.
    cardTheme: const CardThemeData(
      color: _previewDarkCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppLayout.cardRadius)),
        side: BorderSide(color: _previewDarkBorder),
      ),
    ),
    // iOS-style component shaping (Nov 7) — same as the light theme,
    // in the dark emerald tokens. See _lightTheme for the rationale.
    dialogTheme: const DialogThemeData(
      backgroundColor: _previewDarkCard,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.all(Radius.circular(AppLayout.dialogRadius)),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: _previewDarkCard,
      modalBackgroundColor: _previewDarkCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      showDragHandle: true,
      dragHandleColor: _previewDarkBorder,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: _previewDarkElevated,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: _previewDarkBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: _previewDarkBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)),
        borderSide: BorderSide(color: _primary, width: 1.5),
      ),
      hintStyle: TextStyle(color: _previewDarkSubtext),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackOutlineWidth: const WidgetStatePropertyAll(0),
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? _primary
            : _previewDarkBorder,
      ),
    ),
    // iOS-style components (Nov 7): see _lightTheme — same emerald
    // Cupertino override, dark brightness.
    cupertinoOverrideTheme: iosCupertinoTheme(Brightness.dark).noDefault(),
  );
}

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

class EstudyanteGOApp extends StatefulWidget {
  const EstudyanteGOApp({
    super.key,
    this.initialSidebarCollapsed = false,
    this.initialThemeMode = ThemeMode.dark,
    this.authService,
    this.permissionService,
  });

  final bool initialSidebarCollapsed;
  final ThemeMode initialThemeMode;

  /// Auth backend. Null in tests that pump the app directly means
  /// "Firebase not configured" (gate falls back to the dashboard).
  final AuthService? authService;

  /// Notification permission backend. Null means the real
  /// permission_handler implementation.
  final PermissionService? permissionService;

  @override
  State<EstudyanteGOApp> createState() => _EstudyanteGOAppState();
}

class _EstudyanteGOAppState extends State<EstudyanteGOApp> {
  // The gate state sits above MaterialApp, so its own context has no
  // Navigator. Route pushes (profile setup) and dialogs (notification
  // prompt) go through this key instead.
  final _navigatorKey = GlobalKey<NavigatorState>();

  late ThemeMode _themeMode = widget.initialThemeMode;
  late final AuthService _authService =
      widget.authService ?? FirebaseAuthService(isConfigured: false);
  late final PermissionService _permissionService =
      widget.permissionService ?? AppPermissionService();

  // ---- First-time gate state ----
  AppStartDestination? _destination;
  AuthMode _authMode = AuthMode.signIn;

  /// True when the sign-in screen was reached from onboarding (the
  /// first-launch path). Only then does auth get a back button, and
  /// it returns to the welcome state (onboarding page 4). Every other
  /// path into sign-in (sign-out, verify escape hatch, fallbacks)
  /// has no back target, so no back button is shown there.
  bool _cameFromOnboarding = false;
  int _onboardingInitialPage = 0;
  AuthUser? _user;
  UserProfile? _profile;
  ProfileStore? _store;
  int _tabIndex = 0;

  /// Remote student-profile store, behind the same `isConfigured`
  /// gate as the shared-posts repository: null when Firebase is not
  /// configured, so the gate never touches Firestore on unconfigured
  /// builds (and widget tests pumping the app without a service keep
  /// the legacy local-only behavior).
  StudentProfileRepository? get _profileRepository =>
      _authService.isConfigured ? FirestoreStudentProfileRepository() : null;

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
    setState(() => _themeMode = mode);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, mode.name);
    } catch (_) {
      // Theme already switched in memory; a failed local save is not fatal.
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
    final profileDone =
        user == null ? false : store.isProfileSetupDone(user.uid);
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
    unawaited(ErrorLogService.instance.record(
      category: ErrorCategory.startup,
      message: 'Dashboard init: destination set to dashboard.',
      startupStage: StartupStage.dashboardInit.name,
      severity: ErrorSeverity.info,
    ));
    setState(() => _destination = AppStartDestination.dashboard);
    if (promptForNotifications && _user != null && _store != null) {
      final store = _store!;
      if (!store.notificationPromptShown) {
        // Show once, right after first authenticated arrival. The flag
        // is set before the dialog so it never repeats, whatever the
        // user chooses.
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          await store.markNotificationPromptShown();
          if (!mounted) return;
          final promptContext = _navigatorKey.currentContext;
          if (promptContext == null) return;
          await showNotificationPermissionPrompt(
            promptContext,
            _permissionService,
          );
        });
      }
    }
  }

  Future<void> _afterAuth(AuthUser user) async {
    _user = user;
    final store = _store ?? ProfileStore(await SharedPreferences.getInstance());
    _store = store;
    if (!user.emailVerified) {
      setState(() => _destination = AppStartDestination.verifyEmail);
      return;
    }
    // Restore first so the setup screen (when shown) is prefilled
    // with saved fields, and a complete restored profile goes
    // straight to the dashboard instead of setup.
    await _restoreProfileForUser(user);
    if (!store.isProfileSetupDone(user.uid)) {
      setState(() => _destination = AppStartDestination.profileSetup);
      return;
    }
    _profile = store.loadProfile(user.uid);
    _goDashboard(promptForNotifications: true);
  }

  Future<void> _afterVerified(AuthUser user) async {
    _user = user;
    final store = _store ?? ProfileStore(await SharedPreferences.getInstance());
    _store = store;
    await _restoreProfileForUser(user);
    if (!store.isProfileSetupDone(user.uid)) {
      setState(() => _destination = AppStartDestination.profileSetup);
      return;
    }
    _profile = store.loadProfile(user.uid);
    _goDashboard(promptForNotifications: true);
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
    setState(() {
      _user = null;
      _profile = null;
      _cameFromOnboarding = false;
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
      home: _gateWidget(),
    );
  }

  Widget _gateWidget() {
    final destination = _destination;
    if (destination == null) {
      return SplashScreen(
        resolve: _resolveStart,
        onDestination: (next) => setState(() => _destination = next),
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
              _authMode = AuthMode.createAccount;
              _cameFromOnboarding = true;
              _destination = AppStartDestination.signIn;
            });
          },
          onSignIn: () async {
            await _markOnboardingDone();
            if (!mounted) return;
            setState(() {
              _authMode = AuthMode.signIn;
              _cameFromOnboarding = true;
              _destination = AppStartDestination.signIn;
            });
          },
          themeMode: _themeMode,
          onThemeModeChanged: _setThemeMode,
          initialPage: _onboardingInitialPage,
        );
      case AppStartDestination.signIn:
        return AuthScreen(
          service: _authService,
          initialMode: _authMode,
          onSignedIn: _afterAuth,
          onAccountCreated: (user) {
            _user = user;
            setState(() => _destination = AppStartDestination.verifyEmail);
          },
          themeMode: _themeMode,
          onThemeModeChanged: _setThemeMode,
          onBack: _cameFromOnboarding ? _backToOnboarding : null,
        );
      case AppStartDestination.verifyEmail:
        final user = _user;
        if (user == null) {
          // Should not happen (verify implies a user), but never trap
          // the user on a screen that needs one.
          return AuthScreen(
            service: _authService,
            initialMode: AuthMode.signIn,
            onSignedIn: _afterAuth,
            onAccountCreated: (created) {
              _user = created;
              setState(() => _destination = AppStartDestination.verifyEmail);
            },
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
              _destination = AppStartDestination.signIn;
            });
          },
        );
      case AppStartDestination.profileSetup:
        final user = _user;
        final store = _store;
        if (user == null || store == null) {
          return AuthScreen(
            service: _authService,
            initialMode: AuthMode.signIn,
            onSignedIn: _afterAuth,
            onAccountCreated: (created) {
              _user = created;
              setState(() => _destination = AppStartDestination.verifyEmail);
            },
            themeMode: _themeMode,
            onThemeModeChanged: _setThemeMode,
          );
        }
        return ProfileSetupScreen(
          user: user,
          store: store,
          profileRepository: _profileRepository,
          initial: _profile,
          onSaved: (profile) {
            _profile = profile;
            _goDashboard(promptForNotifications: true);
          },
        );
      case AppStartDestination.dashboard:
        return _HomeShell(
          initialSidebarCollapsed: widget.initialSidebarCollapsed,
          themeMode: _themeMode,
          onThemeModeChanged: _setThemeMode,
          selectedIndex: _tabIndex,
          onSelect: _selectTab,
          authService: _authService,
          user: _user,
          profile: _profile,
          permissionService: _permissionService,
          onViewStudent: () => _selectTab(0),
          onViewCommunities: () => _selectTab(4),
          onEditProfile: () => _openProfileSetup(isEdit: true),
          onSignInRequested: () {
            setState(() {
              _authMode = AuthMode.signIn;
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
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.selectedIndex,
    required this.onSelect,
    required this.authService,
    required this.user,
    required this.profile,
    required this.permissionService,
    required this.onViewStudent,
    required this.onViewCommunities,
    required this.onEditProfile,
    required this.onSignInRequested,
    required this.onSignedOut,
  });

  final bool initialSidebarCollapsed;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final AuthService authService;
  final AuthUser? user;
  final UserProfile? profile;
  final PermissionService permissionService;
  final VoidCallback onViewStudent;
  final VoidCallback onViewCommunities;
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
  late final PointsWalletController _walletController =
      PointsWalletController(
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

  @override
  void initState() {
    super.initState();
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
      unawaited(ErrorLogService.instance.record(
        category: ErrorCategory.startup,
        message: 'Ads init skipped (Safe Mode).',
        startupStage: 'adsInit',
        severity: ErrorSeverity.warning,
      ));
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
            walletController: _walletController,
            creditsController: _creditsController,
            adService: _adService,
          ),
        ),
        StudyTab(walletController: _walletController),
        FaresTab(
          onViewOnMap: () => widget.onSelect(3),
          currentUser: widget.user,
          customRouteRepository:
              widget.authService.isConfigured
                  ? FirestoreCustomRouteRepository()
                  : LocalCustomRouteRepository(),
          fareOverrideRepository:
              widget.authService.isConfigured
                  ? FirestoreRouteFareOverrideRepository()
                  : LocalRouteFareOverrideRepository(),
          busStopRepository:
              widget.authService.isConfigured
                  ? FirestoreBusStopRepository()
                  : LocalBusStopRepository(),
          busCompanyRepository:
              widget.authService.isConfigured
                  ? FirestoreBusCompanyRepository()
                  : LocalBusCompanyRepository(),
        ),
        MapTab(
          currentUser: widget.user,
          visible: widget.selectedIndex == 3,
          customRouteRepository:
              widget.authService.isConfigured
                  ? FirestoreCustomRouteRepository()
                  : LocalCustomRouteRepository(),
          fareOverrideRepository:
              widget.authService.isConfigured
                  ? FirestoreRouteFareOverrideRepository()
                  : LocalRouteFareOverrideRepository(),
          busStopRepository:
              widget.authService.isConfigured
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
          themeMode: widget.themeMode,
          onThemeModeChanged: widget.onThemeModeChanged,
          authService: widget.authService,
          user: widget.user,
          profile: widget.profile,
          permissionService: widget.permissionService,
          walletController: _walletController,
          creditsController: _creditsController,
          adService: _adService,
          onViewStudent: widget.onViewStudent,
          onViewCommunities: widget.onViewCommunities,
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

    if (wide) {
      return Scaffold(
        appBar: AppBar(title: Text(_destinations[widget.selectedIndex].label)),
        // Top inset is handled by the AppBar; left/right/bottom insets
        // (gesture bar, cutouts) are respected here.
        body: SafeArea(
          top: false,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Sidebar(
                collapsed: _collapsed,
                selectedIndex: widget.selectedIndex,
                onSelect: widget.onSelect,
                onToggle: _toggleSidebar,
              ),
              // Expanded content stays responsive while the sidebar
              // animates; no overflow, no layout shift of the content.
              Expanded(child: animatedBody),
            ],
          ),
        ),
      );
    }

    // Phones (preview port, Nov 6): the plain "EstudyanteGO"
    // wordmark header + the icon-only top nav directly under it.
    // There is NO bottom nav on phones anymore (the floating
    // glass capsule / iOS glass bar are retired); the top nav is
    // the only tab switcher. The wide branch above is untouched.
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _PhoneHeader(onBell: () => _showNotifications(context)),
            TopNavBar(
              selectedIndex: widget.selectedIndex,
              onSelect: widget.onSelect,
              destinations: [
                for (final d in _destinations)
                  TopNavDestination(d.label, d.icon, d.selectedIcon),
              ],
            ),
            Expanded(child: animatedBody),
          ],
        ),
      ),
    );
  }

  /// Header bell: the app has no notification system, so this is
  /// the same honest empty state the Student tab bell shows — never
  /// a fake unread dot.
  void _showNotifications(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const Padding(
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
              'This app does not have a notification system yet, so there is nothing to show here.',
              style: AppText.caption,
            ),
          ],
        ),
      ),
    );
  }
}

/// Phone header (preview port, Nov 6): plain styled "EstudyanteGO"
/// wordmark — bold, emerald gradient lettering, short gradient
/// underline bar, NO logo mark — plus the notifications bell.
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
    final scheme = Theme.of(context).colorScheme;
    // Preview wordmark: deep emerald → brand on light; bright
    // accent → brand on dark, so the wordmark stays readable on the
    // #0c1410 page instead of sinking into it.
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final wordmarkColors = isDark
        ? const [_previewAccent, _primary]
        : const [_deepEmerald, _primary];
    return Container(
      color: scheme.surface,
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => LinearGradient(
                    colors: wordmarkColors,
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ).createShader(bounds),
                  child: const Text(
                    'EstudyanteGO',
                    style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 48,
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: wordmarkColors,
                    ),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('header-notifications'),
            icon: const Icon(Icons.notifications_outlined),
            tooltip: 'Notifications',
            onPressed: onBell,
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
                border: Border(right: BorderSide(color: scheme.outline)),
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
                          const Expanded(
                            child: Text(
                              'EstudyanteGO',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
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
        color: selected ? _primary : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            height: 56,
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
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? Colors.white : muted,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
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
            color: selected ? _primary : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                width: 48,
                height: 48,
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
    );
  }
}

/// Small branded mark: emerald rounded square with a bus icon.
class _LogoMark extends StatelessWidget {
  const _LogoMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: _primary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.directions_bus, color: Colors.white, size: 22),
    );
  }
}
