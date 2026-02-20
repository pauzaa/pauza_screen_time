import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:pauza_screen_time/src/core/background_channel_runner.dart';
import 'package:pauza_screen_time/src/core/cancel_token.dart';
import 'package:pauza_screen_time/src/features/installed_apps/installed_apps_platform.dart';
import 'package:pauza_screen_time/src/features/installed_apps/method_channel/channel_name.dart';
import 'package:pauza_screen_time/src/features/installed_apps/method_channel/method_names.dart';
import 'package:pauza_screen_time/src/features/installed_apps/model/app_info.dart';

/// Method-channel implementation for the Installed Apps feature.
class InstalledAppsMethodChannel extends InstalledAppsPlatform {
  @visibleForTesting
  final MethodChannel channel;

  InstalledAppsMethodChannel({MethodChannel? channel})
    : channel = channel ?? const MethodChannel(installedAppsChannelName);

  @override
  Future<List<AppInfo>> getInstalledApps(
    bool includeSystemApps, {
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (Platform.isIOS) {
      throw UnsupportedError('getInstalledApps() is only supported on Android.');
    }

    final result = await BackgroundChannelRunner.invokeMethod<List<dynamic>>(
      channel.name,
      InstalledAppsMethodNames.getInstalledApps,
      arguments: {'includeSystemApps': includeSystemApps, 'includeIcons': includeIcons},
      cancelToken: cancelToken,
      timeout: timeout,
    );
    if (result == null) return const [];
    try {
      return result.map((entry) => AppInfo.fromMap(Map<String, dynamic>.from(entry as Map))).toList();
    } catch (error, stackTrace) {
      throw _decodeFailure(
        action: InstalledAppsMethodNames.getInstalledApps,
        message: 'Failed to decode installed apps payload',
        payload: result,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<AppInfo?> getAppInfo(
    String packageId, {
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (Platform.isIOS) {
      throw UnsupportedError('getAppInfo() is only supported on Android.');
    }

    final result = await BackgroundChannelRunner.invokeMethod<Map<dynamic, dynamic>?>(
      channel.name,
      InstalledAppsMethodNames.getAppInfo,
      arguments: {'packageId': packageId, 'includeIcons': includeIcons},
      cancelToken: cancelToken,
      timeout: timeout,
    );
    if (result == null) return null;
    try {
      return AppInfo.fromMap(Map<String, dynamic>.from(result));
    } catch (error, stackTrace) {
      throw _decodeFailure(
        action: InstalledAppsMethodNames.getAppInfo,
        message: 'Failed to decode app info payload',
        payload: result,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<List<IOSAppInfo>> showFamilyActivityPicker({List<String>? preSelectedTokens}) async {
    if (Platform.isAndroid) {
      throw UnsupportedError('showFamilyActivityPicker() is only supported on iOS.');
    }

    final result = await channel.invokeMethod<List<dynamic>>(InstalledAppsMethodNames.showFamilyActivityPicker, {
      'preSelectedTokens': preSelectedTokens ?? [],
    });
    if (result == null) return const [];
    try {
      return result.map((entry) => IOSAppInfo.fromMap(Map<String, dynamic>.from(entry as Map))).toList();
    } catch (error, stackTrace) {
      throw _decodeFailure(
        action: InstalledAppsMethodNames.showFamilyActivityPicker,
        message: 'Failed to decode iOS picker payload',
        payload: result,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  PlatformException _decodeFailure({
    required String action,
    required String message,
    Object? payload,
    Object? error,
    StackTrace? stackTrace,
  }) {
    return PlatformException(
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
  }
}
