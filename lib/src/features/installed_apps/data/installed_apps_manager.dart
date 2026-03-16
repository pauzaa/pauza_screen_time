import 'package:flutter/services.dart';
import 'package:pauza_screen_time/src/core/core.dart';
import 'package:pauza_screen_time/src/features/installed_apps/installed_apps_platform.dart';
import 'package:pauza_screen_time/src/features/installed_apps/method_channel/installed_apps_method_channel.dart';
import 'package:pauza_screen_time/src/features/installed_apps/model/app_info.dart';

/// Manages installed applications enumeration.
class InstalledAppsManager {
  final InstalledAppsPlatform _platform;

  InstalledAppsManager({InstalledAppsPlatform? platform}) : _platform = platform ?? InstalledAppsMethodChannel();

  // ============================================================
  // Android-Only Methods
  // ============================================================

  /// Returns a list of all installed applications on Android.
  ///
  /// **Android only** - Throws [UnsupportedError] on other platforms.
  ///
  /// [includeSystemApps] - Whether to include system apps (default: false).
  /// [includeIcons] - Whether to include app icons (default: true).
  Future<List<AndroidAppInfo>> getAndroidInstalledApps({
    bool includeSystemApps = false,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    assertAndroid('getAndroidInstalledApps');

    final result = await _platform
        .getInstalledApps(includeSystemApps, includeIcons: includeIcons, cancelToken: cancelToken, timeout: timeout)
        .throwTypedPauzaError();
    final apps = <AndroidAppInfo>[];
    for (var index = 0; index < result.length; index++) {
      final appInfo = result[index];
      if (appInfo is! AndroidAppInfo) {
        throw _typedDecodeFailure(
          action: 'getAndroidInstalledApps',
          message: 'Expected Android app payload at index $index, but got ${appInfo.runtimeType}',
          payload: appInfo,
        );
      }
      apps.add(appInfo);
    }
    return apps;
  }

  /// Returns information about a specific Android app by package ID.
  ///
  /// **Android only** - Throws [UnsupportedError] on other platforms.
  ///
  /// [packageId] - Package identifier of the app (e.g., "com.example.app").
  /// [includeIcons] - Whether to include app icons (default: true).
  /// Returns null if the app is not found.
  Future<AndroidAppInfo?> getAndroidAppInfo(
    AppIdentifier packageId, {
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    assertAndroid('getAndroidAppInfo');

    final result = await _platform
        .getAppInfo(packageId.raw, includeIcons: includeIcons, cancelToken: cancelToken, timeout: timeout)
        .throwTypedPauzaError();
    if (result == null) return null;

    final appInfo = result;
    if (appInfo is! AndroidAppInfo) {
      throw _typedDecodeFailure(
        action: 'getAndroidAppInfo',
        message: 'Expected Android app payload, but got ${appInfo.runtimeType}',
        payload: appInfo,
      );
    }
    return appInfo;
  }

  /// Checks if a specific Android app is installed.
  ///
  /// **Android only** - Throws [UnsupportedError] on other platforms.
  ///
  /// [packageId] - Package identifier of the app.
  /// Returns true if the app is installed, false otherwise.
  Future<bool> isAndroidAppInstalled(AppIdentifier packageId) async {
    assertAndroid('isAndroidAppInstalled');

    final appInfo = await getAndroidAppInfo(packageId);
    return appInfo != null;
  }

  // ============================================================
  // iOS-Only Methods
  // ============================================================

  /// Shows the iOS FamilyActivityPicker for user to select apps.
  ///
  /// **iOS only** - Throws [UnsupportedError] on other platforms.
  ///
  /// [preSelectedApps] - Optional list of previously selected apps that should
  /// appear pre-selected when the picker opens. Pass apps retrieved from a
  /// previous [selectIOSApps] call or from your local storage.
  ///
  /// Returns a list of opaque selection tokens as [IOSAppInfo] objects.
  ///
  /// iOS does not allow enumerating installed apps. Persist these tokens yourself
  /// if you want to re-open the picker with a previous selection.
  Future<List<IOSAppInfo>> selectIOSApps({List<IOSAppInfo>? preSelectedApps}) async {
    assertIOS('selectIOSApps');

    // Extract tokens from pre-selected apps
    final preSelectedTokens = preSelectedApps?.map((app) => app.applicationToken.raw).toList();

    final result = await _platform
        .showFamilyActivityPicker(preSelectedTokens: preSelectedTokens)
        .throwTypedPauzaError();
    return result;
  }

  PauzaInternalFailureError _typedDecodeFailure({
    required String action,
    required String message,
    Object? payload,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final exception = PlatformException(
      code: 'INTERNAL_FAILURE',
      message: message,
      details: <String, Object?>{
        'feature': 'installed_apps',
        'action': action,
        'platform': 'dart',
        if (payload != null) 'payloadType': payload.runtimeType.toString(),
        if (error != null) 'errorType': error.runtimeType.toString(),
        if (error != null || stackTrace != null)
          'diagnostic': [if (error != null) error.toString(), if (stackTrace != null) stackTrace.toString()].join('\n'),
      },
    );
    return PauzaError.fromPlatformException(exception) as PauzaInternalFailureError;
  }
}
