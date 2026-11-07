// One-time notification permission prompt.
//
// Shown once after sign-in/profile setup, never at launch, never again
// after either choice (the caller records the shown flag). The copy is
// honest: it explains what notifications are for and that the choice
// can change anytime in system settings.
import 'package:flutter/material.dart';

import '../ios_components.dart';
import 'permission_service.dart';

/// Shows the explanation dialog and, when the user taps Allow, requests
/// the OS permission. Returns true when notifications end up granted.
Future<bool> showNotificationPermissionPrompt(
  BuildContext context,
  PermissionService service,
) async {
  final allow = await showIosAlert<bool>(
    context: context,
    barrierDismissible: false,
    title: 'Stay updated?',
    message: 'EstudyanteGO can send you notifications about community updates '
        'and service alerts. You can change this anytime in your device '
        'settings.',
    actions: const [
      IosAlertAction<bool>('Not now', value: false),
      IosAlertAction<bool>('Allow', value: true, isDefault: true),
    ],
  );
  if (allow != true) return false;
  final status = await service.requestNotification();
  return status == NotificationPermissionStatus.granted;
}
