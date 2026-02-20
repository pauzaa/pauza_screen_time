import 'dart:io' show Platform;

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

  UsageStatsManager({UsageStatsPlatform? platform}) : _platform = platform ?? UsageStatsMethodChannel();

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

    return result;
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

    return result;
  }
}
