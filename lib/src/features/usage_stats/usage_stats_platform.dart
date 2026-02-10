import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:pauza_screen_time/src/core/cancel_token.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_usage_stats.dart';

/// Platform interface for usage statistics functionality.
abstract class UsageStatsPlatform extends PlatformInterface {
  UsageStatsPlatform() : super(token: _token);

  static final Object _token = Object();

  /// Queries usage statistics for all apps within the specified time range.
  ///
  /// **Android only** - Returns a list of maps containing usage data.
  /// **iOS** - Not supported; use platform view for usage reports.
  Future<List<UsageStats>> queryUsageStats({
    required int startTimeMs,
    required int endTimeMs,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) {
    throw UnimplementedError('queryUsageStats() has not been implemented.');
  }

  /// Queries usage statistics for a specific app.
  ///
  /// **Android only** - Returns a map containing usage data, or null if app not found.
  /// **iOS** - Not supported; use platform view for usage reports.
  Future<UsageStats?> queryAppUsageStats({
    required String packageId,
    required int startTimeMs,
    required int endTimeMs,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) {
    throw UnimplementedError('queryAppUsageStats() has not been implemented.');
  }
}
