// Login Alerts + Session Manager — the 'Was this you?' dialog.
//
// Shown when a sign-in from another device is detected (see
// SessionService.onForeignSession). Copy follows the approved
// preview v1: the notification title, the device/time/location
// rows, and the two answers. 'Yes' marks the session trusted;
// 'No' starts the secure-my-account flow (handled by the caller).
import 'package:flutter/material.dart';

import 'security_theme.dart';
import 'session_models.dart';

enum LoginAlertChoice { yesThatWasMe, noSecureMyAccount }

/// Shows the login-alert dialog for [session] and returns the
/// owner's answer, or null when dismissed without answering.
Future<LoginAlertChoice?> showLoginAlertDialog({
  required BuildContext context,
  required UserSession session,
}) {
  return showDialog<LoginAlertChoice>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: kSecurityDeepLeaves, width: 3),
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: kSecurityGold.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kSecurityDirt, width: 3),
              ),
              child: const Icon(
                Icons.shield_outlined,
                color: kSecurityDeepLeaves,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'New sign-in to your EstudyanteGO account',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Someone just signed in to your account. If this was '
              'you, no action is needed. If it wasn\'t you, secure '
              'your account right away.',
            ),
            const SizedBox(height: 16),
            _DetailRow(
              label: 'Device',
              value: session.detailLine,
            ),
            const SizedBox(height: 8),
            _DetailRow(
              label: 'Time',
              value:
                  '${formatTimeOfDay(session.createdAt)} · ${formatMonthDay(session.createdAt)}',
            ),
            if (session.locationLabel != null) ...[
              const SizedBox(height: 8),
              _DetailRow(
                label: 'Location',
                value: session.locationLabel!,
              ),
            ],
            const SizedBox(height: 16),
            const Text(
              'Don\'t recognize this sign-in? Tap "No" below — the '
              'other device gets signed out and you\'ll be asked to '
              'change your password.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 8),
            const Text(
              'Was this you?',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            style: securityDangerButtonStyle(context),
            onPressed: () => Navigator.of(context).pop(
              LoginAlertChoice.noSecureMyAccount,
            ),
            child: const Text('No, secure my account'),
          ),
          FilledButton(
            style: securityBlockButtonStyle(context),
            onPressed: () => Navigator.of(context).pop(
              LoginAlertChoice.yesThatWasMe,
            ),
            child: const Text('Yes, that was me'),
          ),
        ],
      );
    },
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
