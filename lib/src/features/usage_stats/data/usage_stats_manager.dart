import 'dart:io' show Platform;

import 'package:pauza_screen_time/src/core/cancel_token.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/usage_stats/method_channel/usage_stats_method_channel.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_standby_bucket.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_usage_stats.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/event_stats.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/usage_event.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/usage_stats_interval.dart';
import 'package:pauza_screen_time/src/features/usage_stats/usage_stats_platform.dart';

/// Manager for app usage statistics.
///
/// All methods are **Android only**. On iOS, use the DeviceActivityReport
/// platform view for usage statistics.
class UsageStatsManager {
  final UsageStatsPlatform _platform;

  UsageStatsManager({UsageStatsPlatform? platform}) : _platform = platform ?? UsageStatsMethodChannel();

  // ============================================================
  // Per-app usage stats (Android only)
  // ============================================================

  /// Returns usage statistics for all apps within the specified time range.
  ///
  /// Throws [PauzaUnsupportedError] on iOS.
  Future<List<UsageStats>> getUsageStats({
    required DateTime startDate,
    required DateTime endDate,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _assertAndroid('getUsageStats');

    return _platform
        .queryUsageStats(
          startTime: startDate,
          endTime: endDate,
          includeIcons: includeIcons,
          cancelToken: cancelToken,
          timeout: timeout,
        )
        .throwTypedPauzaError();
  }

  /// Returns usage statistics for a specific app.
  ///
  /// Returns null if the app has no foreground usage in the given range.
  ///
  /// Throws [PauzaUnsupportedError] on iOS.
  Future<UsageStats?> getAppUsageStats({
    required String packageId,
    required DateTime startDate,
    required DateTime endDate,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _assertAndroid('getAppUsageStats');

    return _platform
        .queryAppUsageStats(
          packageId: packageId,
          startTime: startDate,
          endTime: endDate,
          includeIcons: includeIcons,
          cancelToken: cancelToken,
          timeout: timeout,
        )
        .throwTypedPauzaError();
  }

  // ============================================================
  // Raw usage events (Android only)
  // ============================================================

  /// Returns raw timestamped usage events for the specified time range.
  ///
  /// If [eventTypes] is non-null, only events of those types are returned.
  /// Events are only kept by the system for a few days.
  ///
  /// Throws [PauzaUnsupportedError] on iOS.
  Future<List<UsageEvent>> getUsageEvents({
    required DateTime startDate,
    required DateTime endDate,
    List<UsageEventType>? eventTypes,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    _assertAndroid('getUsageEvents');

    return _platform
        .queryUsageEvents(
          startTime: startDate,
          endTime: endDate,
          eventTypes: eventTypes,
          cancelToken: cancelToken,
          timeout: timeout,
        )
        .throwTypedPauzaError();
  }

  // ============================================================
  // Aggregated device event stats (Android only, API 28+)
  // ============================================================

  /// Returns aggregated event stats (screen on/off, lock/unlock) for the time range.
  ///
  /// Throws a [PauzaError] on Android < 9 (API 28).
  ///
  /// Throws [PauzaUnsupportedError] on iOS.
  Future<List<DeviceEventStats>> getEventStats({
    required DateTime startDate,
    required DateTime endDate,
    UsageStatsInterval intervalType = UsageStatsInterval.best,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _assertAndroid('getEventStats');

    return _platform
        .queryEventStats(
          startTime: startDate,
          endTime: endDate,
          intervalType: intervalType,
          cancelToken: cancelToken,
          timeout: timeout,
        )
        .throwTypedPauzaError();
  }

  // ============================================================
  // App inactivity (Android only)
  // ============================================================

  /// Returns whether the specified app is currently considered inactive.
  ///
  /// Throws [PauzaUnsupportedError] on iOS.
  Future<bool> isAppInactive({
    required String packageId,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _assertAndroid('isAppInactive');

    return _platform
        .isAppInactive(packageId: packageId, cancelToken: cancelToken, timeout: timeout)
        .throwTypedPauzaError();
  }

  // ============================================================
  // App standby bucket (Android only, API 28+)
  // ============================================================

  /// Returns the standby bucket of the **calling** app.
  ///
  /// Throws a [PauzaError] on Android < 9 (API 28).
  ///
  /// Throws [PauzaUnsupportedError] on iOS.
  Future<AppStandbyBucket> getAppStandbyBucket({
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _assertAndroid('getAppStandbyBucket');

    return _platform.getAppStandbyBucket(cancelToken: cancelToken, timeout: timeout).throwTypedPauzaError();
  }

  // ============================================================
  // Private helpers
  // ============================================================

  void _assertAndroid(String methodName) {
    if (!Platform.isAndroid) {
      throw const PauzaUnsupportedError(
        message:
            'This method is only supported on Android. '
            'On iOS, use the DeviceActivityReport platform view.',
        rawCode: 'UNSUPPORTED',
      );
    }
  }
}
