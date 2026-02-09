import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'package:pauza_screen_time/src/core/cancel_token.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/usage_stats/method_channel/usage_stats_method_channel.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_usage_stats.dart';
import 'package:pauza_screen_time/src/features/usage_stats/usage_stats_platform.dart';

/// Manager for app usage statistics.
///
/// **Platform Support:**
/// - **Android**: Full support via UsageStatsManager API
/// - **iOS**: Not supported (use DeviceActivityReport platform view instead)
class UsageStatsManager {
  final UsageStatsPlatform _platform;

  UsageStatsManager({UsageStatsPlatform? platform})
    : _platform = platform ?? UsageStatsMethodChannel();

  // ============================================================
  // Usage Stats Queries (Android Only)
  // ============================================================

  /// Returns usage statistics for all apps within the specified time range.
  ///
  /// **Android only** - This method is not supported on iOS.
  ///
  /// Throws [UnsupportedError] if called on iOS.
  Future<List<UsageStats>> getUsageStats({
    required DateTime startDate,
    required DateTime endDate,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!Platform.isAndroid) {
      throw const PauzaUnsupportedError(
        message:
            'getUsageStats() is only supported on Android. On iOS, use DeviceActivityReport platform view for usage statistics.',
        rawCode: 'UNSUPPORTED',
      );
    }

    final result = await _platform
        .queryUsageStats(
          startTimeMs: startDate.millisecondsSinceEpoch,
          endTimeMs: endDate.millisecondsSinceEpoch,
          includeIcons: includeIcons,
          cancelToken: cancelToken,
          timeout: timeout,
        )
        .throwTypedPauzaError();

    final stats = <UsageStats>[];
    for (var index = 0; index < result.length; index++) {
      stats.add(
        _decodeUsageStats(
          payload: result[index],
          action: 'getUsageStats',
          index: index,
        ),
      );
    }
    return stats;
  }

  /// Returns usage statistics for a specific app.
  ///
  /// **Android only** - This method is not supported on iOS.
  ///
  /// Throws [UnsupportedError] if called on iOS.
  Future<UsageStats?> getAppUsageStats({
    required String packageId,
    required DateTime startDate,
    required DateTime endDate,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!Platform.isAndroid) {
      throw const PauzaUnsupportedError(
        message:
            'getAppUsageStats() is only supported on Android. On iOS, use DeviceActivityReport platform view for usage statistics.',
        rawCode: 'UNSUPPORTED',
      );
    }

    final result = await _platform
        .queryAppUsageStats(
          packageId: packageId,
          startTimeMs: startDate.millisecondsSinceEpoch,
          endTimeMs: endDate.millisecondsSinceEpoch,
          includeIcons: includeIcons,
          cancelToken: cancelToken,
          timeout: timeout,
        )
        .throwTypedPauzaError();

    if (result == null) return null;
    return _decodeUsageStats(payload: result, action: 'getAppUsageStats');
  }

  UsageStats _decodeUsageStats({
    required Object? payload,
    required String action,
    int? index,
  }) {
    try {
      return UsageStats.fromMap(Map<String, dynamic>.from(payload as Map));
    } on PlatformException catch (exception) {
      throw PauzaError.fromPlatformException(exception);
    } catch (error, stackTrace) {
      throw PauzaError.fromPlatformException(
        PlatformException(
          code: 'INTERNAL_FAILURE',
          message: index == null
              ? 'Failed to decode usage stats payload'
              : 'Failed to decode usage stats payload at index $index',
          details: <String, Object?>{
            'feature': 'usage_stats',
            'action': action,
            'platform': 'dart',
            'payloadType': payload.runtimeType.toString(),
            'errorType': error.runtimeType.toString(),
            'diagnostic': '${error.toString()}\n${stackTrace.toString()}',
          },
        ),
      );
    }
  }
}
