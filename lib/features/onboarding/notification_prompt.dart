// One-time notification permission prompt.
//
// Shown once after sign-in/profile setup, never at launch, never again
// after either choice (the caller records the shown flag). The copy is
// honest: it explains what notifications are for and that the choice
// can change anytime in system settings.
import 'package:flutter/material.dart';

import 'permission_service.dart';

/// Shows the explanation dialog and, when the user taps Allow, requests
/// the OS permission. Returns true when notifications end up granted.
Future<bool> showNotificationPermissionPrompt(
  BuildContext context,
  PermissionService service,
) async {
  final allow = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Stay updated?'),
      content: const Text(
        'EstudyanteGO can send you notifications about community updates '
        'and service alerts. You can change this anytime in your device '
        'settings.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Allow'),
        ),
      ],
    ),
  );
  if (allow != true) return false;
  final status = await service.requestNotification();
  return status == NotificationPermissionStatus.granted;
}
