import 'package:flutter/foundation.dart';
import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/core/map_helpers.dart' as helpers;
import 'package:pauza_screen_time/src/features/installed_apps/model/app_info.dart';

/// Usage statistics for an application over a time period.
///
/// This model captures all data available from Android's UsageStats API,
/// including app metadata (name, icon), usage duration, launch counts,
/// and timestamps that define the statistics bucket and recency.
@immutable
class UsageStats {
  /// Information about the application (package name, label, icon).
  final AndroidAppInfo appInfo;

  /// Total time the app was in the foreground.
  final Duration totalDuration;

  /// Total number of times the app was launched.
  final int totalLaunchCount;

  /// Start time of the statistics bucket (Android only).
  /// Represents when this UsageStats measurement period began.
  final DateTime? bucketStart;

  /// End time of the statistics bucket (Android only).
  /// Represents when this UsageStats measurement period ended.
  final DateTime? bucketEnd;

  /// Timestamp when app was last used in foreground (Android only).
  final DateTime? lastTimeUsed;

  /// Timestamp when app was last visible (Android Q+ only).
  /// This tracks when the app was last visible, even if not in foreground/focused.
  final DateTime? lastTimeVisible;

  const UsageStats({
    required this.appInfo,
    required this.totalDuration,
    required this.totalLaunchCount,
    this.bucketStart,
    this.bucketEnd,
    this.lastTimeUsed,
    this.lastTimeVisible,
  });

  /// Creates a UsageStats from a map (used for platform channel deserialization).
  factory UsageStats.fromMap(Map<String, dynamic> map) {
    final rawIcon = map['appIcon'];
    final icon = rawIcon is Uint8List
        ? rawIcon
        : rawIcon is List
        ? Uint8List.fromList(List<int>.from(rawIcon))
        : null;

    return UsageStats(
      appInfo: AndroidAppInfo(
        packageId: AppIdentifier.android(map['packageId'] as String),
        name: map['appName'] as String? ?? map['packageId'] as String,
        icon: icon,
        category: map['category'] as String?,
        isSystemApp: map['isSystemApp'] as bool? ?? false,
      ),
      totalDuration: Duration(milliseconds: helpers.asInt(map['totalDurationMs'])),
      totalLaunchCount: helpers.asInt(map['totalLaunchCount']),
      bucketStart: _optionalDateTime(map['bucketStartMs'] ?? map['firstTimeStampMs']),
      bucketEnd: _optionalDateTime(map['bucketEndMs'] ?? map['lastTimeStampMs']),
      lastTimeUsed: _optionalDateTime(map['lastTimeUsedMs']),
      lastTimeVisible: _optionalDateTime(map['lastTimeVisibleMs']),
    );
  }

  /// Converts this UsageStats to a map (used for platform channel serialization).
  Map<String, dynamic> toMap() {
    return {
      'packageId': appInfo.packageId,
      'appName': appInfo.name,
      'totalDurationMs': totalDuration.inMilliseconds,
      'totalLaunchCount': totalLaunchCount,
      'appIcon': appInfo.icon?.toList(),
      'category': appInfo.category,
      'isSystemApp': appInfo.isSystemApp,
      'bucketStartMs': bucketStart?.millisecondsSinceEpoch,
      'bucketEndMs': bucketEnd?.millisecondsSinceEpoch,
      'lastTimeUsedMs': lastTimeUsed?.millisecondsSinceEpoch,
      'lastTimeVisibleMs': lastTimeVisible?.millisecondsSinceEpoch,
    };
  }

  // ============================================================
  // Private helpers
  // ============================================================

  static DateTime? _optionalDateTime(dynamic ms) {
    if (ms == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(helpers.asInt(ms));
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UsageStats &&
        other.appInfo == appInfo &&
        other.totalDuration == totalDuration &&
        other.totalLaunchCount == totalLaunchCount;
  }

  @override
  int get hashCode => Object.hash(appInfo, totalDuration, totalLaunchCount);

  @override
  String toString() => 'UsageStats(appInfo: $appInfo, totalDuration: $totalDuration, launches: $totalLaunchCount)';
}
