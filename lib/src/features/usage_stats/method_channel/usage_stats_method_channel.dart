import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:pauza_screen_time/src/core/background_channel_runner.dart';
import 'package:pauza_screen_time/src/core/cancel_token.dart';
import 'package:pauza_screen_time/src/features/usage_stats/usage_stats_platform.dart';
import 'package:pauza_screen_time/src/features/usage_stats/method_channel/channel_name.dart';
import 'package:pauza_screen_time/src/features/usage_stats/method_channel/method_names.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_usage_stats.dart';

/// Method-channel implementation for the Usage Stats feature.
///
/// Note: on iOS this feature is intentionally unsupported at the channel level.
/// Consumers should use the `UsageReportView` platform view instead.
class UsageStatsMethodChannel extends UsageStatsPlatform {
  @visibleForTesting
  final MethodChannel channel;

  UsageStatsMethodChannel({MethodChannel? channel})
    : channel = channel ?? const MethodChannel(usageStatsChannelName);

  @override
  Future<List<UsageStats>> queryUsageStats({
    required int startTimeMs,
    required int endTimeMs,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (Platform.isIOS) {
      throw UnsupportedError(
        'queryUsageStats() is only supported on Android. '
        'On iOS, use DeviceActivityReport platform view for usage statistics.',
      );
    }

    final result = await BackgroundChannelRunner.invokeMethod<List<dynamic>>(
      channel.name,
      UsageStatsMethodNames.queryUsageStats,
      arguments: {
        'startTimeMs': startTimeMs,
        'endTimeMs': endTimeMs,
        'includeIcons': includeIcons,
      },
      cancelToken: cancelToken,
      timeout: timeout,
    );
    if (result == null) return const [];
    try {
      return result
          .map(
            (entry) =>
                UsageStats.fromMap(Map<String, dynamic>.from(entry as Map)),
          )
          .toList();
    } catch (error, stackTrace) {
      throw _decodeFailure(
        action: UsageStatsMethodNames.queryUsageStats,
        message: 'Failed to decode usage stats payload',
        payload: result,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<UsageStats?> queryAppUsageStats({
    required String packageId,
    required int startTimeMs,
    required int endTimeMs,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (Platform.isIOS) {
      throw UnsupportedError(
        'queryAppUsageStats() is only supported on Android. '
        'On iOS, use DeviceActivityReport platform view for usage statistics.',
      );
    }

    final result =
        await BackgroundChannelRunner.invokeMethod<Map<dynamic, dynamic>?>(
          channel.name,
          UsageStatsMethodNames.queryAppUsageStats,
          arguments: {
            'packageId': packageId,
            'startTimeMs': startTimeMs,
            'endTimeMs': endTimeMs,
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
        'feature': 'usage_stats',
        'action': action,
        'platform': 'dart',
        if (payload != null) 'payloadType': payload.runtimeType.toString(),
        if (error != null) 'errorType': error.runtimeType.toString(),
        if (error != null || stackTrace != null)
          'diagnostic': [
            if (error != null) error.toString(),
            if (stackTrace != null) stackTrace.toString(),
          ].join('\n'),
      },
    );
  }
}
