import 'package:flutter/foundation.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/usage_event.dart';

/// Aggregated event statistics for a device-level event type over a time period.
///
/// Returned by [UsageStatsManager.queryEventStats]. Each instance represents a
/// single event type — typically one of:
/// - [UsageEventType.screenInteractive] — screen-on sessions
/// - [UsageEventType.screenNonInteractive] — screen-off periods
/// - [UsageEventType.keyguardShown] — lock screen appearances
/// - [UsageEventType.keyguardHidden] — device unlocks
///
/// **Android 9 (API 28) and above only.**
@immutable
class DeviceEventStats {
  /// The event type these statistics apply to.
  final UsageEventType eventType;

  /// Number of times this event occurred in the queried interval.
  final int count;

  /// Total time this state was active across all occurrences.
  ///
  /// For [UsageEventType.screenInteractive] this equals total screen-on time.
  /// For [UsageEventType.keyguardHidden] this equals total time the device was unlocked.
  final Duration totalTime;

  /// Start of the measurement interval.
  final DateTime firstTimestamp;

  /// End of the measurement interval.
  final DateTime lastTimestamp;

  /// The last time this event triggered.
  final DateTime lastEventTime;

  const DeviceEventStats({
    required this.eventType,
    required this.count,
    required this.totalTime,
    required this.firstTimestamp,
    required this.lastTimestamp,
    required this.lastEventTime,
  });

  /// Constructs a [DeviceEventStats] from the map returned by the method channel.
  factory DeviceEventStats.fromMap(Map<String, dynamic> map) {
    return DeviceEventStats(
      eventType: UsageEventType.fromRawValue(_asInt(map['eventType'])),
      count: _asInt(map['count']),
      totalTime: Duration(milliseconds: _asInt(map['totalTimeMs'])),
      firstTimestamp: DateTime.fromMillisecondsSinceEpoch(_asInt(map['firstTimestampMs'])),
      lastTimestamp: DateTime.fromMillisecondsSinceEpoch(_asInt(map['lastTimestampMs'])),
      lastEventTime: DateTime.fromMillisecondsSinceEpoch(_asInt(map['lastEventTimeMs'])),
    );
  }

  /// Converts this [DeviceEventStats] to a map suitable for platform channel transfer.
  ///
  /// The resulting map is the inverse of [fromMap], enabling round-trip testing.
  Map<String, dynamic> toMap() => {
    'eventType': eventType.rawValue,
    'count': count,
    'totalTimeMs': totalTime.inMilliseconds,
    'firstTimestampMs': firstTimestamp.millisecondsSinceEpoch,
    'lastTimestampMs': lastTimestamp.millisecondsSinceEpoch,
    'lastEventTimeMs': lastEventTime.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceEventStats &&
        other.eventType == eventType &&
        other.count == count &&
        other.totalTime == totalTime;
  }

  @override
  int get hashCode => Object.hash(eventType, count, totalTime);

  @override
  String toString() => 'DeviceEventStats(eventType: $eventType, count: $count, totalTime: $totalTime)';

  /// Safe numeric-to-int cast for platform channel payloads.
  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    throw ArgumentError.value(value, 'value', 'Expected a numeric type, got ${value.runtimeType}');
  }
}
