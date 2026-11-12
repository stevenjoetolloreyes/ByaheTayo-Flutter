// Tests for the Login Alerts + Session Manager models and pure
// helpers (no Firebase, no device): failure-reason mapping, device
// labels, time formatting, day grouping, session sorting, and the
// offline nearest-place location label.
import 'package:estudyantego/features/security/session_location.dart';
import 'package:estudyantego/features/security/session_models.dart';
import 'package:flutter_test/flutter_test.dart';

UserSession session({
  required String id,
  required DateTime lastActiveAt,
}) {
  return UserSession(
    id: id,
    uid: 'uid-1',
    deviceLabel: 'Android phone',
    platform: 'android',
    formFactor: 'phone',
    signInMethod: 'email',
    createdAt: lastActiveAt,
    lastActiveAt: lastActiveAt,
  );
}

LoginAttempt attempt({
  required String id,
  required DateTime at,
  bool success = true,
  String reason = '',
}) {
  return LoginAttempt(
    id: id,
    uid: 'uid-1',
    success: success,
    reason: reason,
    deviceLabel: 'Android phone',
    platform: 'android',
    signInMethod: 'email',
    createdAt: at,
  );
}

void main() {
  group('failureReasonForCode', () {
    test('wrong-password codes map to the preview label', () {
      expect(failureReasonForCode('wrong-password'), 'wrong password');
      expect(failureReasonForCode('invalid-credential'), 'wrong password');
    });

    test('other codes map honestly', () {
      expect(failureReasonForCode('user-not-found'), 'account not found');
      expect(failureReasonForCode('too-many-requests'), 'too many attempts');
      expect(failureReasonForCode('network-request-failed'), 'network error');
      expect(failureReasonForCode('no-account'), 'no account found');
      expect(failureReasonForCode('bogus-code'), 'sign-in failed');
      expect(failureReasonForCode(null), 'sign-in failed');
    });
  });

  group('deviceLabelFor', () {
    test('phone vs tablet wording matches the preview', () {
      expect(
        deviceLabelFor(platform: 'android', isTablet: false),
        'Android phone',
      );
      expect(
        deviceLabelFor(platform: 'android', isTablet: true),
        'Android tablet',
      );
      expect(deviceLabelFor(platform: 'ios', isTablet: false), 'iPhone');
      expect(deviceLabelFor(platform: 'ios', isTablet: true), 'iPad');
      expect(deviceLabelFor(platform: 'web', isTablet: false), 'Web browser');
      expect(deviceLabelFor(platform: 'windows', isTablet: false),
          'Windows PC');
      expect(deviceLabelFor(platform: 'mystery', isTablet: false),
          'Unknown device');
    });
  });

  group('time formatting', () {
    test('12-hour clock', () {
      expect(formatTimeOfDay(DateTime(2026, 11, 11, 22, 24)), '10:24 PM');
      expect(formatTimeOfDay(DateTime(2026, 11, 11, 0, 5)), '12:05 AM');
      expect(formatTimeOfDay(DateTime(2026, 11, 11, 12, 0)), '12:00 PM');
    });

    test('day-relative stamps', () {
      final now = DateTime(2026, 11, 11, 22, 30);
      expect(
        formatDayTime(DateTime(2026, 11, 11, 20, 12), now: now),
        'Today, 8:12 PM',
      );
      expect(
        formatDayTime(DateTime(2026, 11, 10, 21, 47), now: now),
        'Yesterday, 9:47 PM',
      );
      expect(
        formatDayTime(DateTime(2026, 11, 9, 7, 5), now: now),
        'Nov 9, 7:05 AM',
      );
    });

    test('day group headers', () {
      final now = DateTime(2026, 11, 11, 22, 30); // Wednesday.
      expect(dayGroupHeader(DateTime(2026, 11, 11), now: now).label, 'TODAY');
      expect(
        dayGroupHeader(DateTime(2026, 11, 11), now: now).sublabel,
        'Wed · Nov 11',
      );
      expect(
        dayGroupHeader(DateTime(2026, 11, 10), now: now).label,
        'YESTERDAY',
      );
      expect(
        dayGroupHeader(DateTime(2026, 11, 9), now: now).label,
        'NOV 9',
      );
    });
  });

  group('UserSession', () {
    test('lastActiveLabel says Active now, then a stamp', () {
      final now = DateTime(2026, 11, 11, 22, 30);
      expect(
        session(id: 'a', lastActiveAt: DateTime(2026, 11, 11, 22, 28))
            .lastActiveLabel(now: now),
        'Active now',
      );
      expect(
        session(id: 'a', lastActiveAt: DateTime(2026, 11, 11, 20, 12))
            .lastActiveLabel(now: now),
        'Last active: Today, 8:12 PM',
      );
    });

    test('detailLine mirrors the preview', () {
      expect(session(id: 'a', lastActiveAt: DateTime.now()).detailLine,
          'Android phone · EstudyanteGO app');
      final web = UserSession(
        id: 'w',
        uid: 'uid-1',
        deviceLabel: 'Web browser',
        platform: 'web',
        formFactor: 'desktop',
        signInMethod: 'email',
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
      );
      expect(web.detailLine, 'Web browser sign-in');
    });

    test('sortSessions puts the current session first', () {
      final older = session(id: 'old', lastActiveAt: DateTime(2026, 11, 10));
      final newer =
          session(id: 'new', lastActiveAt: DateTime(2026, 11, 11, 9));
      final current =
          session(id: 'cur', lastActiveAt: DateTime(2026, 11, 9));
      final sorted = sortSessions(
        [older, newer, current],
        currentSessionId: 'cur',
      );
      expect(sorted.map((s) => s.id).toList(), ['cur', 'new', 'old']);
    });
  });

  group('LoginAttempt', () {
    test('titleLine mirrors the preview', () {
      expect(
        attempt(id: 'a', at: DateTime.now()).titleLine,
        'Signed in',
      );
      expect(
        attempt(
          id: 'b',
          at: DateTime.now(),
          success: false,
          reason: 'wrong password',
        ).titleLine,
        'Failed sign-in — wrong password',
      );
      final google = LoginAttempt(
        id: 'c',
        uid: 'uid-1',
        success: true,
        reason: '',
        deviceLabel: 'Android phone',
        platform: 'android',
        signInMethod: 'google',
        createdAt: DateTime.now(),
      );
      expect(google.titleLine, 'Signed in with Google');
    });

    test('groupAttemptsByDay groups newest-first', () {
      final grouped = groupAttemptsByDay([
        attempt(id: 'old', at: DateTime(2026, 11, 10, 7, 5)),
        attempt(id: 'new', at: DateTime(2026, 11, 11, 22, 24)),
        attempt(
          id: 'mid',
          at: DateTime(2026, 11, 11, 20, 12),
          success: false,
          reason: 'wrong password',
        ),
      ]);
      expect(grouped.length, 2);
      expect(grouped[0].day, DateTime(2026, 11, 11));
      expect(
        grouped[0].attempts.map((a) => a.id).toList(),
        ['new', 'mid'],
      );
      expect(grouped[1].attempts.map((a) => a.id).toList(), ['old']);
    });
  });

  group('locationLabelFor (offline nearest bundled place)', () {
    test('Vigan City labels with its province, not its region', () {
      expect(locationLabelFor(17.56138, 120.38564), 'Vigan City, Ilocos Sur');
    });

    test('Cabugao and Laoag label correctly', () {
      expect(locationLabelFor(17.78916, 120.45838), 'Cabugao, Ilocos Sur');
      expect(locationLabelFor(18.20207, 120.53721), 'Laoag City, Ilocos Norte');
    });

    test('far from any bundled place there is no label', () {
      expect(locationLabelFor(0, 0), isNull);
      // Mid-Pacific, far from every Philippine place.
      expect(locationLabelFor(10.0, -150.0), isNull);
    });
  });
}
