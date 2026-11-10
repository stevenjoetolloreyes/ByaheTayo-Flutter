// Google Calendar sync (Feature 4 of the Classes + menu build, Nov 10,
// 2026): wire the menu's "Google Schedule" option to the user's REAL
// Google Calendar.
//
// REAL SYNC — not the mock: the app's existing Google Sign-In
// (google_sign_in 7.x, the same account flow Firebase Auth uses)
// authorizes the read-only Calendar scope
// (https://www.googleapis.com/auth/calendar.readonly), and the
// Calendar v3 REST API (calendars/primary/events) fetches the
// student's own upcoming events. No new dependency: the HTTP call
// is plain dart:io HttpClient, the same approach osm_routing.dart
// already uses. No googleapis package, no http package.
//
// HONESTY RULE: only events actually returned by the Calendar API
// are ever added. The 4 sample events in google_events.dart
// (Discrete Mathematics, Life and Works of Rizal, NSTP 1, Vigan)
// are placeholders from the hub-card preview, NOT the user's real
// calendar — they are never presented as synced results, and the
// first successful real sync replaces the stored set with the real
// events. When the real sync cannot run (Calendar API not enabled
// in the Google Cloud project, the calendar scope not added to the
// OAuth consent screen, or the Android OAuth client missing),
// the flow reports [GoogleCalendarSyncStatus.setupMissing] with
// the exact Console steps — it never shows a fake
// "connected/synced" state and never invents events.
//
// What the sync reads: the signed-in student's own primary
// calendar only, upcoming events in the next 28 days, timed
// events only (all-day events have no class time and are skipped),
// recurring events expanded to one entry per weekday occurrence.
// It never touches anyone else's calendar, and it never writes to
// the calendar — read-only scope.
//
// What Steven must do first (Google Cloud Console, project
// estudyantego — only he can do this; see the setup-missing
// dialog in classes_screen.dart): enable the Google Calendar API,
// add the calendar.readonly scope to the OAuth consent screen,
// and make sure an Android OAuth client exists for
// com.estudyantego.app (the google-services.json in this repo
// currently lists NO OAuth client at all).
import 'dart:convert';
import 'dart:io';

import 'package:google_sign_in/google_sign_in.dart';

import '../onboarding/firebase_auth_service.dart';
import 'google_events.dart';

/// Read-only Calendar scope: the sync reads the student's own
/// calendar and never writes to it.
const googleCalendarReadonlyScope =
    'https://www.googleapis.com/auth/calendar.readonly';

/// How far ahead a sync looks: upcoming events in the next 28 days
/// (covers weekly classes and monthly patterns).
const googleCalendarSyncWindowDays = 28;

/// Phases reported to the progress dialog while a sync runs, so
/// the UI can say what is actually happening — connect first,
/// then fetch. No fake progress: the phase changes only when the
/// real step starts.
enum GoogleCalendarSyncPhase { connecting, syncing }

/// What happened when a sync ran.
enum GoogleCalendarSyncStatus {
  /// The student dismissed the account chooser / consent screen.
  cancelled,

  /// Real events came back from the Calendar API.
  synced,

  /// Connected and fetched fine, but no timed events in the window.
  noEvents,

  /// The real sync cannot run yet: the Calendar API is not
  /// enabled, the calendar scope is not on the OAuth consent
  /// screen, or the Android OAuth client is missing. The UI shows
  /// the exact Console steps instead of a fake success.
  setupMissing,

  /// A network / API failure that is not a setup problem.
  failed,
}

/// The outcome of one sync run.
class GoogleCalendarSyncResult {
  const GoogleCalendarSyncResult({
    required this.status,
    this.events = const [],
    this.accountEmail = '',
  });

  final GoogleCalendarSyncStatus status;

  /// Events actually fetched from the Calendar API (non-empty
  /// only when [status] is [GoogleCalendarSyncStatus.synced]).
  final List<GoogleCalendarEvent> events;

  /// The Google account the sync read, for the empty-state text.
  final String accountEmail;
}

/// The signed-in Google account + an access token carrying the
/// calendar.readonly scope.
class GoogleCalendarConnection {
  const GoogleCalendarConnection({
    required this.accessToken,
    required this.email,
  });

  final String accessToken;
  final String email;
}

/// Thrown inside the real connect/fetch steps to say the run ended
/// because the student cancelled (chooser / consent dismissed).
class GoogleCalendarCancelled implements Exception {}

/// Thrown inside the real connect/fetch steps to say the run ended
/// because the Calendar setup is missing (API not enabled, scope
/// not on the consent screen, OAuth client missing, token
/// rejected). The UI turns this into the setup-missing dialog.
class GoogleCalendarSetupMissing implements Exception {
  const GoogleCalendarSetupMissing([this.detail = '']);

  final String detail;
}

/// Real Google Calendar sync: connect (Google Sign-In + calendar
/// scope) then fetch (Calendar v3 events.list).
///
/// The connect step, the fetch step, and the whole run are
/// injectable so widget tests can run without native plugins or
/// network (both deadlock in `flutter test`'s fake-async zone —
/// the Files scan fakes its picker/extractor for the same reason).
/// The real connect/fetch paths are covered by plain `test()`s
/// over the pure parser in test/google_calendar_sync_test.dart.
class GoogleCalendarSync {
  GoogleCalendarSync({
    Future<GoogleCalendarConnection> Function()? connect,
    Future<List<GoogleCalendarEvent>> Function(String accessToken)?
        fetchEvents,
  })  : _connectOverride = connect,
        _fetchOverride = fetchEvents;

  final Future<GoogleCalendarConnection> Function()? _connectOverride;
  final Future<List<GoogleCalendarEvent>> Function(String accessToken)?
      _fetchOverride;

  /// Connect, then fetch, reporting the real phase as each step
  /// starts. Never throws: every failure maps to a [status] the
  /// UI can show honestly.
  Future<GoogleCalendarSyncResult> sync({
    required void Function(GoogleCalendarSyncPhase phase) onPhase,
  }) async {
    onPhase(GoogleCalendarSyncPhase.connecting);
    late final GoogleCalendarConnection connection;
    try {
      connection = await (_connectOverride ?? _realConnect)();
    } on GoogleCalendarCancelled {
      return const GoogleCalendarSyncResult(
          status: GoogleCalendarSyncStatus.cancelled);
    } on GoogleCalendarSetupMissing {
      return const GoogleCalendarSyncResult(
          status: GoogleCalendarSyncStatus.setupMissing);
    } catch (_) {
      return const GoogleCalendarSyncResult(
          status: GoogleCalendarSyncStatus.failed);
    }
    onPhase(GoogleCalendarSyncPhase.syncing);
    try {
      final events =
          await (_fetchOverride ?? _realFetch)(connection.accessToken);
      if (events.isEmpty) {
        return GoogleCalendarSyncResult(
          status: GoogleCalendarSyncStatus.noEvents,
          accountEmail: connection.email,
        );
      }
      return GoogleCalendarSyncResult(
        status: GoogleCalendarSyncStatus.synced,
        events: events,
        accountEmail: connection.email,
      );
    } on GoogleCalendarSetupMissing {
      return const GoogleCalendarSyncResult(
          status: GoogleCalendarSyncStatus.setupMissing);
    } catch (_) {
      return const GoogleCalendarSyncResult(
          status: GoogleCalendarSyncStatus.failed);
    }
  }

  /// Real connect: the app's existing Google Sign-In, then the
  /// calendar.readonly scope authorization.
  ///
  /// - The Google account is the one the student picks in the
  ///   native chooser (or the already-signed-in Google account,
  ///   via lightweight auth). This signs into Google only — it
  ///   never touches Firebase Auth, so the strict Google sign-in
  ///   rule (login-only, never auto-create a profile) is
  ///   untouched: no Firebase credential is created here.
  /// - A scope authorization already granted returns silently;
  ///   otherwise the consent screen appears.
  /// - [GoogleSignInExceptionCode.clientConfigurationError] (no
  ///   OAuth client configured) and scope errors map to
  ///   setup-missing; a dismissed chooser/consent maps to
  ///   cancelled.
  Future<GoogleCalendarConnection> _realConnect() async {
    try {
      await FirebaseAuthService.ensureGoogleInitialized();
    } catch (_) {
      throw const GoogleCalendarSetupMissing(
          'Google Sign-In could not start.');
    }
    GoogleSignInAccount? account;
    try {
      account = await GoogleSignIn.instance
              .attemptLightweightAuthentication() ??
          await GoogleSignIn.instance.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw GoogleCalendarCancelled();
      }
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError) {
        throw const GoogleCalendarSetupMissing(
            'No OAuth client is configured for this app.');
      }
      // A scope that is not on the consent screen surfaces here
      // as an unknown error mentioning the scope.
      if ((e.description ?? '').toLowerCase().contains('scope')) {
        throw const GoogleCalendarSetupMissing(
            'The calendar scope is not set up.');
      }
      rethrow;
    }
    GoogleSignInClientAuthorization? authz;
    try {
      authz = await account.authorizationClient
              .authorizationForScopes([googleCalendarReadonlyScope]) ??
          await account.authorizationClient
              .authorizeScopes([googleCalendarReadonlyScope]);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled ||
          e.code == GoogleSignInExceptionCode.interrupted) {
        throw GoogleCalendarCancelled();
      }
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError) {
        throw const GoogleCalendarSetupMissing(
            'No OAuth client is configured for this app.');
      }
      if ((e.description ?? '').toLowerCase().contains('scope')) {
        throw const GoogleCalendarSetupMissing(
            'The calendar scope is not set up.');
      }
      rethrow;
    }
    return GoogleCalendarConnection(
      accessToken: authz.accessToken,
      email: account.email,
    );
  }

  /// Real fetch: Calendar v3 events.list on the primary calendar,
  /// recurring events expanded, ordered by start time, Asia/Manila
  /// wall-clock times.
  Future<List<GoogleCalendarEvent>> _realFetch(String accessToken) async {
    final now = DateTime.now();
    final uri = Uri.https(
      'www.googleapis.com',
      '/calendar/v3/calendars/primary/events',
      {
        'singleEvents': 'true',
        'orderBy': 'startTime',
        'timeMin': now.toUtc().toIso8601String(),
        'timeMax': now
            .add(const Duration(days: googleCalendarSyncWindowDays))
            .toUtc()
            .toIso8601String(),
        'maxResults': '250',
        'timeZone': 'Asia/Manila',
      },
    );
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.headers
          .set(HttpHeaders.authorizationHeader, 'Bearer $accessToken');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response =
          await request.close().timeout(const Duration(seconds: 20));
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401) {
        throw const GoogleCalendarSetupMissing(
            'Google rejected the calendar access token.');
      }
      if (response.statusCode == 403) {
        // Calendar API not enabled (accessNotConfigured) or the
        // scope was not granted: both are Console setup.
        throw const GoogleCalendarSetupMissing(
            'Google Calendar API is not enabled or the scope was not granted.');
      }
      if (response.statusCode != 200) {
        throw HttpException(
            'Calendar API returned ${response.statusCode}.');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Unexpected Calendar API response.');
      }
      return parseCalendarEvents(decoded);
    } finally {
      client.close();
    }
  }
}

/// Calendar API colors, cycled in start-time order. (Google's own
/// colorId values are not mapped — the timetable already colors
/// each entry from this palette family.)
const _syncedEventColors = [
  0xFF16A34A,
  0xFF2563EB,
  0xFF7C3AED,
  0xFFEA580C,
  0xFF0D9488,
  0xFFDB2777,
  0xFFDC2626,
  0xFFCA8A04,
];

/// Manila wall clock (UTC+8, no DST) for an absolute [instant]:
/// weekday 1-7 and minutes since midnight.
({int weekday, int startMin}) _manilaWallClock(DateTime instant) {
  final manila = instant.toUtc().add(const Duration(hours: 8));
  return (weekday: manila.weekday, startMin: manila.hour * 60 + manila.minute);
}

/// Parse one Calendar v3 events.list response into timetable
/// events — pure Dart, no I/O, covered by plain `test()`s.
///
/// - Cancelled events, all-day events (a `date` with no
///   `dateTime` — no class time to place), and untitled events are
///   skipped, never guessed into a slot.
/// - A recurring event expands to one entry per weekday occurrence
///   (singleEvents=true); identical occurrences dedupe to one.
/// - End at/before start, or longer than 12 hours, is skipped.
/// - Ids are `gcal-<googleId>-<weekday>`: one entry per weekday
///   occurrence, so a Mon/Wed/Fri class never collides with itself
///   in the stored set. Ids never collide with the placeholder
///   sample set (`g-nstp` etc.) or with manual subjects.
List<GoogleCalendarEvent> parseCalendarEvents(Map<String, dynamic> json) {
  final items = json['items'];
  if (items is! List) return [];
  final out = <GoogleCalendarEvent>[];
  final seen = <String>{};
  var colorIndex = 0;
  for (final raw in items) {
    if (raw is! Map<String, dynamic>) continue;
    if (raw['status'] == 'cancelled') continue;
    final summary = (raw['summary'] as String?)?.trim() ?? '';
    if (summary.isEmpty) continue;
    final start = raw['start'];
    final end = raw['end'];
    if (start is! Map<String, dynamic>) continue;
    final startText = start['dateTime'] as String?;
    if (startText == null) continue; // All-day event: no time.
    final startDt = DateTime.tryParse(startText);
    if (startDt == null) continue;
    final endDt = end is Map<String, dynamic>
        ? DateTime.tryParse(end['dateTime'] as String? ?? '')
        : null;
    final startWall = _manilaWallClock(startDt);
    final endMin = endDt == null
        ? startWall.startMin + 60
        : _manilaWallClock(endDt).startMin;
    if (endMin <= startWall.startMin) continue;
    if (endMin - startWall.startMin > 12 * 60) continue;
    final googleId = raw['id'] as String? ?? '';
    if (googleId.isEmpty) continue;
    final id = 'gcal-$googleId-${startWall.weekday}';
    if (!seen.add(id)) continue;
    out.add(GoogleCalendarEvent(
      id: id,
      title: summary,
      weekday: startWall.weekday,
      startMin: startWall.startMin,
      endMin: endMin,
      place: (raw['location'] as String?)?.trim() ?? '',
      color: _syncedEventColors[colorIndex % _syncedEventColors.length],
    ));
    colorIndex++;
  }
  return out;
}
