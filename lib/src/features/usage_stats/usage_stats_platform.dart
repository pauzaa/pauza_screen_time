import 'package:pauza_screen_time/src/core/cancel_token.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_standby_bucket.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_usage_stats.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/event_stats.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/usage_event.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/usage_stats_interval.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Platform interface for usage statistics functionality.
abstract class UsageStatsPlatform extends PlatformInterface {
  UsageStatsPlatform() : super(token: _token);

  static final Object _token = Object();

  // ============================================================
  // Per-app usage stats
  // ============================================================

  /// Queries usage statistics for all apps within the specified time range.
  ///
  /// **Android only** — iOS is not supported at the channel level.
  /// Use the `UsageReportView` platform view on iOS instead.
  Future<List<UsageStats>> queryUsageStats({
    required DateTime startTime,
    required DateTime endTime,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) {
    throw UnimplementedError('queryUsageStats() has not been implemented.');
  }

  /// Queries usage statistics for a specific app.
  ///
  /// Returns null if the app has no foreground usage in the given range.
  ///
  /// **Android only.**
  Future<UsageStats?> queryAppUsageStats({
    required String packageId,
    required DateTime startTime,
    required DateTime endTime,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) {
    throw UnimplementedError('queryAppUsageStats() has not been implemented.');
  }

  // ============================================================
  // Raw usage events
  // ============================================================

  /// Queries raw usage events for the specified time range.
  ///
  /// Events are kept by the system for only a few days. If [eventTypes] is
  /// non-null, only events of those types are returned.
  ///
  /// **Android only.**
  Future<List<UsageEvent>> queryUsageEvents({
    required DateTime startTime,
    required DateTime endTime,
    List<UsageEventType>? eventTypes,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 60),
  }) {
    throw UnimplementedError('queryUsageEvents() has not been implemented.');
  }

  // ============================================================
  // Aggregated device event stats (API 28+)
  // ============================================================

  /// Queries aggregated event stats (screen on/off, lock/unlock) for the time range.
  ///
  /// Throws [PlatformException] with code `INTERNAL_FAILURE` on Android < 9 (API 28).
  ///
  /// **Android only.**
  Future<List<DeviceEventStats>> queryEventStats({
    required DateTime startTime,
    required DateTime endTime,
    UsageStatsInterval intervalType = UsageStatsInterval.best,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) {
    throw UnimplementedError('queryEventStats() has not been implemented.');
  }

  // ============================================================
  // App inactivity
  // ============================================================

  /// Returns whether the specified app is currently considered inactive.
  ///
  /// **Android only.**
  Future<bool> isAppInactive({
    required String packageId,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 10),
  }) {
    throw UnimplementedError('isAppInactive() has not been implemented.');
  }

  // ============================================================
  // App standby bucket (API 28+)
  // ============================================================

  /// Returns the standby bucket of the **calling** app.
  ///
  /// Throws [PlatformException] with code `INTERNAL_FAILURE` on Android < 9 (API 28).
  ///
  /// **Android only.**
  Future<AppStandbyBucket> getAppStandbyBucket({
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 10),
  }) {
    throw UnimplementedError('getAppStandbyBucket() has not been implemented.');
  }
}
