import 'dart:io';

import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/permissions/method_channel/permissions_method_channel.dart';
import 'package:pauza_screen_time/src/features/permissions/model/android_permission.dart';
import 'package:pauza_screen_time/src/features/permissions/model/ios_permission.dart';
import 'package:pauza_screen_time/src/features/permissions/model/permission_status.dart';
import 'package:pauza_screen_time/src/features/permissions/permission_platform.dart';

/// Manages platform-specific permissions.
class PermissionManager {
  final PermissionPlatform _platform;

  PermissionManager({PermissionPlatform? platform})
    : _platform = platform ?? PermissionsMethodChannel();

  // ============================================================
  // Android Permissions
  // ============================================================

  /// Checks the status of an Android permission.
  ///
  /// Only call this on Android platform.
  Future<PermissionStatus> checkAndroidPermission(
    AndroidPermission permission,
  ) {
    if (!Platform.isAndroid) {
      throw const PauzaUnsupportedError(
        message: 'checkAndroidPermission is only available on Android',
        rawCode: 'UNSUPPORTED',
      );
    }
    return _platform.checkPermission(permission.key).throwTypedPauzaError();
  }

  /// Starts the Android permission request flow for a permission requirement.
  ///
  /// This call does not return whether permission was granted. Re-check the
  /// permission status when the app resumes.
  ///
  /// For [AndroidPermission.queryAllPackages], this method is a no-op because
  /// it is a manifest/policy capability and not runtime-requestable.
  ///
  /// For [AndroidPermission.exactAlarm], this opens system settings on
  /// Android 12+ where exact alarms are controlled.
  /// Only call this on Android platform.
  Future<void> requestAndroidPermission(AndroidPermission permission) {
    if (!Platform.isAndroid) {
      throw const PauzaUnsupportedError(
        message: 'requestAndroidPermission is only available on Android',
        rawCode: 'UNSUPPORTED',
      );
    }
    if (permission == AndroidPermission.queryAllPackages) {
      return Future<void>.value();
    }
    return _platform.requestPermission(permission.key).throwTypedPauzaError();
  }

  /// Opens the system settings page for the specified Android permission.
  ///
  /// Useful when a permission needs to be granted manually.
  /// Only call this on Android platform.
  Future<void> openAndroidPermissionSettings(AndroidPermission permission) {
    if (!Platform.isAndroid) {
      throw const PauzaUnsupportedError(
        message: 'openAndroidPermissionSettings is only available on Android',
        rawCode: 'UNSUPPORTED',
      );
    }
    return _platform
        .openPermissionSettings(permission.key)
        .throwTypedPauzaError();
  }

  // ============================================================
  // iOS Permissions
  // ============================================================

  /// Checks the status of an iOS permission.
  ///
  /// Only call this on iOS platform.
  Future<PermissionStatus> checkIOSPermission(IOSPermission permission) {
    if (!Platform.isIOS) {
      throw const PauzaUnsupportedError(
        message: 'checkIOSPermission is only available on iOS',
        rawCode: 'UNSUPPORTED',
      );
    }
    return _platform.checkPermission(permission.key).throwTypedPauzaError();
  }

  /// Requests an iOS permission from the user.
  ///
  /// Returns true if the permission was granted.
  /// Only call this on iOS platform.
  Future<bool> requestIOSPermission(IOSPermission permission) {
    if (!Platform.isIOS) {
      throw const PauzaUnsupportedError(
        message: 'requestIOSPermission is only available on iOS',
        rawCode: 'UNSUPPORTED',
      );
    }
    return _platform.requestPermission(permission.key).throwTypedPauzaError();
  }

  // ============================================================
  // Typed Batch Permission Checks
  // ============================================================

  /// Checks the status of multiple Android permissions.
  ///
  /// Returns a typed map of permissions to their status.
  /// Only call this on Android platform.
  Future<Map<AndroidPermission, PermissionStatus>> checkAndroidPermissions(
    List<AndroidPermission> permissions,
  ) async {
    if (!Platform.isAndroid) {
      throw const PauzaUnsupportedError(
        message: 'checkAndroidPermissions is only available on Android',
        rawCode: 'UNSUPPORTED',
      );
    }
    final results = <AndroidPermission, PermissionStatus>{};
    for (final permission in permissions) {
      results[permission] = await _platform
          .checkPermission(permission.key)
          .throwTypedPauzaError();
    }
    return results;
  }

  /// Checks the status of multiple iOS permissions.
  ///
  /// Returns a typed map of permissions to their status.
  /// Only call this on iOS platform.
  Future<Map<IOSPermission, PermissionStatus>> checkIOSPermissions(
    List<IOSPermission> permissions,
  ) async {
    if (!Platform.isIOS) {
      throw const PauzaUnsupportedError(
        message: 'checkIOSPermissions is only available on iOS',
        rawCode: 'UNSUPPORTED',
      );
    }
    final results = <IOSPermission, PermissionStatus>{};
    for (final permission in permissions) {
      results[permission] = await _platform
          .checkPermission(permission.key)
          .throwTypedPauzaError();
    }
    return results;
  }

  /// Returns a list of Android permissions that are not granted.
  ///
  /// If [subset] is provided, only checks those permissions.
  /// Otherwise, checks all Android permissions.
  Future<List<AndroidPermission>> getMissingAndroidPermissions([
    List<AndroidPermission>? subset,
  ]) async {
    if (!Platform.isAndroid) {
      throw const PauzaUnsupportedError(
        message: 'getMissingAndroidPermissions is only available on Android',
        rawCode: 'UNSUPPORTED',
      );
    }
    final permissionsToCheck = subset ?? AndroidPermission.values;
    final statuses = await checkAndroidPermissions(permissionsToCheck);
    return statuses.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key)
        .toList();
  }

  /// Returns a list of iOS permissions that are not granted.
  ///
  /// If [subset] is provided, only checks those permissions.
  /// Otherwise, checks all iOS permissions.
  Future<List<IOSPermission>> getMissingIOSPermissions([
    List<IOSPermission>? subset,
  ]) async {
    if (!Platform.isIOS) {
      throw const PauzaUnsupportedError(
        message: 'getMissingIOSPermissions is only available on iOS',
        rawCode: 'UNSUPPORTED',
      );
    }
    final permissionsToCheck = subset ?? IOSPermission.values;
    final statuses = await checkIOSPermissions(permissionsToCheck);
    return statuses.entries
        .where((entry) => !entry.value.isGranted)
        .map((entry) => entry.key)
        .toList();
  }
}
