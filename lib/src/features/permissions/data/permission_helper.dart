import 'dart:io';

import 'package:pauza_screen_time/src/features/permissions/model/android_permission.dart';
import 'package:pauza_screen_time/src/features/permissions/model/ios_permission.dart';
import 'package:pauza_screen_time/src/features/permissions/model/permission_status.dart';
import 'package:pauza_screen_time/src/features/permissions/data/permission_manager.dart';

/// Helper class for managing permissions.
///
/// This class provides convenience methods to check and request multiple permissions
/// at once, utilizing [PermissionManager].
class PermissionHelper {
  final PermissionManager _permissionManager;

  const PermissionHelper(this._permissionManager);

  /// Checks all required permissions for the current platform.
  ///
  /// Returns a map of permission keys to their status.
  /// Consider using [PermissionManager.checkAndroidPermissions] or
  /// [PermissionManager.checkIOSPermissions] for typed results.
  Future<Map<String, PermissionStatus>> checkAllRequiredPermissions() async {
    final results = <String, PermissionStatus>{};

    if (Platform.isAndroid) {
      final typed = await _permissionManager.checkAndroidPermissions(AndroidPermission.values);
      for (final entry in typed.entries) {
        results[entry.key.key] = entry.value;
      }
    } else if (Platform.isIOS) {
      final typed = await _permissionManager.checkIOSPermissions(IOSPermission.values);
      for (final entry in typed.entries) {
        results[entry.key.key] = entry.value;
      }
    }

    return results;
  }

  /// Opens request flows for required permissions on the current platform.
  ///
  /// On Android this opens only the first missing Settings screen among runtime
  /// prerequisites. On iOS this triggers system authorization requests.
  /// Re-check statuses after the user returns.
  Future<void> requestAllRequiredPermissions() async {
    if (Platform.isAndroid) {
      final missingRuntimePermissions = await _permissionManager.getMissingAndroidPermissions([
        AndroidPermission.usageStats,
        AndroidPermission.accessibility,
        AndroidPermission.exactAlarm,
      ]);
      if (missingRuntimePermissions.isEmpty) {
        return;
      }
      await _permissionManager.requestAndroidPermission(missingRuntimePermissions.first);
      return;
    } else if (Platform.isIOS) {
      final missingPermissions = await _permissionManager.getMissingIOSPermissions();
      if (missingPermissions.isEmpty) {
        return;
      }
      await _permissionManager.requestIOSPermission(missingPermissions.first);
      return;
    }
  }

  /// Checks if all required permissions are granted.
  Future<bool> areAllPermissionsGranted() async {
    final statuses = await checkAllRequiredPermissions();
    return statuses.values.every((status) => status.isGranted);
  }

  /// Returns a list of permissions that are not granted.
  Future<List<String>> getMissingPermissions() async {
    final statuses = await checkAllRequiredPermissions();
    return statuses.entries.where((entry) => !entry.value.isGranted).map((entry) => entry.key).toList();
  }
}
