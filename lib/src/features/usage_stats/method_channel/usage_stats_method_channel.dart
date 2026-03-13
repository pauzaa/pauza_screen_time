import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pauza_screen_time/src/core/background_channel_runner.dart';
import 'package:pauza_screen_time/src/core/cancel_token.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/usage_stats/method_channel/channel_name.dart';
import 'package:pauza_screen_time/src/features/usage_stats/method_channel/method_names.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_standby_bucket.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_usage_stats.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/event_stats.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/usage_event.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/usage_stats_interval.dart';
import 'package:pauza_screen_time/src/features/usage_stats/usage_stats_platform.dart';

/// Method-channel implementation for the Usage Stats feature.
///
/// On iOS this feature is intentionally unsupported at the channel level.
/// Consumers should use the `UsageReportView` platform view instead.
class UsageStatsMethodChannel extends UsageStatsPlatform {
  @visibleForTesting
  final MethodChannel channel;

  UsageStatsMethodChannel({MethodChannel? channel}) : channel = channel ?? const MethodChannel(usageStatsChannelName);

  @override
  Future<List<UsageStats>> queryUsageStats({
    required DateTime startTime,
    required DateTime endTime,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _assertAndroid('queryUsageStats');

    final result = await BackgroundChannelRunner.invokeMethod<List<dynamic>>(
      channel.name,
      UsageStatsMethodNames.queryUsageStats,
      arguments: {
        'startTimeMs': startTime.millisecondsSinceEpoch,
        'endTimeMs': endTime.millisecondsSinceEpoch,
        'includeIcons': includeIcons,
      },
      cancelToken: cancelToken,
      timeout: timeout,
    );
    if (result == null) return const [];
    try {
      return result.map((e) => UsageStats.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    } catch (error, stackTrace) {
      throw _decodeFailure(
        action: UsageStatsMethodNames.queryUsageStats,
        message: 'Failed to decode usage stats payload',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<UsageStats?> queryAppUsageStats({
    required String packageId,
    required DateTime startTime,
    required DateTime endTime,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _assertAndroid('queryAppUsageStats');

    final result = await BackgroundChannelRunner.invokeMethod<Map<dynamic, dynamic>?>(
      channel.name,
      UsageStatsMethodNames.queryAppUsageStats,
      arguments: {
        'packageId': packageId,
        'startTimeMs': startTime.millisecondsSinceEpoch,
        'endTimeMs': endTime.millisecondsSinceEpoch,
        'includeIcons': includeIcons,
      },
      cancelToken: cancelToken,
      timeout: timeout,
    );
    if (result == null) return null;
    try {
      return UsageStats.fromMap(Map<String, dynamic>.from(result));
    } catch (error, stackTrace) {
      throw _decodeFailure(
        action: UsageStatsMethodNames.queryAppUsageStats,
        message: 'Failed to decode app usage stats payload',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<List<UsageEvent>> queryUsageEvents({
    required DateTime startTime,
    required DateTime endTime,
    List<UsageEventType>? eventTypes,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    _assertAndroid('queryUsageEvents');

    final result = await BackgroundChannelRunner.invokeMethod<List<dynamic>>(
      channel.name,
      UsageStatsMethodNames.queryUsageEvents,
      arguments: {
        'startTimeMs': startTime.millisecondsSinceEpoch,
        'endTimeMs': endTime.millisecondsSinceEpoch,
        if (eventTypes != null) 'eventTypes': eventTypes.map((e) => e.rawValue).toList(),
      },
      cancelToken: cancelToken,
      timeout: timeout,
    );
    if (result == null) return const [];
    try {
      return result.map((e) => UsageEvent.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    } catch (error, stackTrace) {
      throw _decodeFailure(
        action: UsageStatsMethodNames.queryUsageEvents,
        message: 'Failed to decode usage events payload',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<List<DeviceEventStats>> queryEventStats({
    required DateTime startTime,
    required DateTime endTime,
    UsageStatsInterval intervalType = UsageStatsInterval.best,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _assertAndroid('queryEventStats');

    final result = await BackgroundChannelRunner.invokeMethod<List<dynamic>>(
      channel.name,
      UsageStatsMethodNames.queryEventStats,
      arguments: {
        'startTimeMs': startTime.millisecondsSinceEpoch,
        'endTimeMs': endTime.millisecondsSinceEpoch,
        'intervalType': intervalType.rawValue,
      },
      cancelToken: cancelToken,
      timeout: timeout,
    );
    if (result == null) return const [];
    try {
      return result.map((e) => DeviceEventStats.fromMap(Map<String, dynamic>.from(e as Map))).toList();
    } catch (error, stackTrace) {
      throw _decodeFailure(
        action: UsageStatsMethodNames.queryEventStats,
        message: 'Failed to decode event stats payload',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<bool> isAppInactive({
    required String packageId,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _assertAndroid('isAppInactive');

    final result = await BackgroundChannelRunner.invokeMethod<bool>(
      channel.name,
      UsageStatsMethodNames.isAppInactive,
      arguments: {'packageId': packageId},
      cancelToken: cancelToken,
      timeout: timeout,
    );
    if (result == null) {
      throw _decodeFailure(
        action: UsageStatsMethodNames.isAppInactive,
        message: 'isAppInactive returned null — expected a boolean',
      );
    }
    return result;
  }

  @override
  Future<AppStandbyBucket> getAppStandbyBucket({
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _assertAndroid('getAppStandbyBucket');

    final result = await BackgroundChannelRunner.invokeMethod<int>(
      channel.name,
      UsageStatsMethodNames.getAppStandbyBucket,
      cancelToken: cancelToken,
      timeout: timeout,
    );
    if (result == null) {
      throw _decodeFailure(
        action: UsageStatsMethodNames.getAppStandbyBucket,
        message: 'getAppStandbyBucket returned null — expected an int',
      );
    }
    return AppStandbyBucket.fromRawValue(result);
  }

  // ============================================================
  // Private helpers
  // ============================================================

  /// Throws [UnsupportedError] if called on iOS.
  void _assertAndroid(String methodName) {
    if (Platform.isIOS) {
      throw UnsupportedError(
        '$methodName() is only supported on Android. '
        'On iOS, use the DeviceActivityReport platform view for usage statistics.',
      );
    }
  }

  PauzaInternalFailureError _decodeFailure({
    required String action,
    required String message,
    Object? error,
    StackTrace? stackTrace,
  }) {
    return PauzaInternalFailureError(
      message: message,
      rawCode: 'INTERNAL_FAILURE',
      details: <String, Object?>{
        'feature': 'usage_stats',
        'action': action,
        'platform': 'dart',
        if (error != null) 'errorType': error.runtimeType.toString(),
        if (error != null || stackTrace != null)
          'diagnostic': [if (error != null) error.toString(), if (stackTrace != null) stackTrace.toString()].join('\n'),
      },
    );
  }
}
