// Notification permission behind an interface, so tests use a fake
// and production uses permission_handler.
//
// Location permission is deliberately NOT handled here: the Map tab
// already requests location only when a map feature needs it
// (Geolocator.checkPermission/requestPermission in map_tab.dart).
// Nothing in the launch flow asks for location.
import 'package:permission_handler/permission_handler.dart' as ph;

/// Current notification-permission state, as the UI shows it.
enum NotificationPermissionStatus { granted, denied, permanentlyDenied, unknown }

abstract class PermissionService {
  Future<NotificationPermissionStatus> notificationStatus();
  Future<NotificationPermissionStatus> requestNotification();
  Future<void> openAppSettings();
}

class AppPermissionService implements PermissionService {
  @override
  Future<NotificationPermissionStatus> notificationStatus() async {
    try {
      return _map(await ph.Permission.notification.status);
    } catch (_) {
      return NotificationPermissionStatus.unknown;
    }
  }

  @override
  Future<NotificationPermissionStatus> requestNotification() async {
    try {
      return _map(await ph.Permission.notification.request());
    } catch (_) {
      return NotificationPermissionStatus.unknown;
    }
  }

  @override
  Future<void> openAppSettings() async {
    try {
      await ph.openAppSettings();
    } catch (_) {
      // Nothing to do: the user stays in the app.
    }
  }

  static NotificationPermissionStatus _map(ph.PermissionStatus status) {
    if (status.isGranted) return NotificationPermissionStatus.granted;
    if (status.isPermanentlyDenied) {
      return NotificationPermissionStatus.permanentlyDenied;
    }
    if (status.isDenied) return NotificationPermissionStatus.denied;
    return NotificationPermissionStatus.unknown;
  }
}
