import 'package:flutter/foundation.dart';
import 'package:pauza_screen_time/src/core/map_helpers.dart' as helpers;

/// Represents a single raw usage event from Android's UsageEvents API.
///
/// Events are only kept by the system for a few days.
///
/// **Android only** — this model has no iOS equivalent.
@immutable
class UsageEvent {
  /// The timestamp when the event occurred.
  final DateTime timestamp;

  /// The package name of the app or system component that generated the event.
  final String packageName;

  /// The activity or service class name. `null` for system-level events such as
  /// [UsageEventType.screenInteractive] or [UsageEventType.keyguardShown].
  final String? className;

  /// The type of this event.
  final UsageEventType eventType;

  const UsageEvent({required this.timestamp, required this.packageName, required this.eventType, this.className});

  /// Constructs a [UsageEvent] from the map returned by the method channel.
  factory UsageEvent.fromMap(Map<String, dynamic> map) {
    return UsageEvent(
      timestamp: DateTime.fromMillisecondsSinceEpoch(helpers.asInt(map['timestampMs'])),
      packageName: map['packageName'] as String,
      className: map['className'] as String?,
      eventType: UsageEventType.fromRawValue(helpers.asInt(map['eventType'])),
    );
  }

  /// Converts this [UsageEvent] to a map suitable for platform channel transfer.
  ///
  /// The resulting map is the inverse of [fromMap], enabling round-trip testing.
  Map<String, dynamic> toMap() => {
    'timestampMs': timestamp.millisecondsSinceEpoch,
    'packageName': packageName,
    'className': className,
    'eventType': eventType.rawValue,
  };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UsageEvent &&
        other.timestamp == timestamp &&
        other.packageName == packageName &&
        other.className == className &&
        other.eventType == eventType;
  }

  @override
  int get hashCode => Object.hash(timestamp, packageName, className, eventType);

  @override
  String toString() => 'UsageEvent(timestamp: $timestamp, package: $packageName, type: $eventType)';
}

/// Event types from [Android's UsageEvents.Event](https://developer.android.com/reference/android/app/usage/UsageEvents.Event).
///
/// Only types available via the public API are listed. The [rawValue]
/// corresponds to the integer constant on the Android side.
enum UsageEventType {
  /// An [Activity] moved to the foreground (API 29+). Replaces [moveToForeground].
  activityResumed(1),

  /// An [Activity] moved to the background (API 29+). Replaces [moveToBackground].
  activityPaused(2),

  /// An [Activity] became invisible on the UI (API 29+).
  activityStopped(23),

  /// The device configuration changed (e.g. rotation).
  configurationChange(5),

  /// The user interacted with a package in some way (API 23+).
  userInteraction(7),

  /// A shortcut was invoked (API 25+).
  shortcutInvocation(8),

  /// The screen turned on for full user interaction (API 28+).
  screenInteractive(15),

  /// The screen turned off or went to a non-interactive state (API 28+).
  screenNonInteractive(16),

  /// The lock screen (keyguard) was displayed (API 28+).
  keyguardShown(17),

  /// The lock screen was dismissed — i.e. the user unlocked the device (API 28+).
  keyguardHidden(18),

  /// A foreground service started (API 29+).
  foregroundServiceStart(19),

  /// A foreground service stopped (API 29+).
  foregroundServiceStop(20),

  /// The Android runtime is shutting down (API 29+).
  deviceShutdown(26),

  /// The Android runtime started up (API 29+).
  deviceStartup(27),

  /// An app's standby bucket changed (API 28+).
  standbyBucketChanged(11),

  /// An event type not recognised by this SDK version.
  unknown(-1);

  /// The raw integer constant from [android.app.usage.UsageEvents.Event].
  final int rawValue;

  const UsageEventType(this.rawValue);

  /// Returns the [UsageEventType] for the given [rawValue], or [unknown]
  /// if the value is not recognised.
  static UsageEventType fromRawValue(int value) {
    for (final type in UsageEventType.values) {
      if (type.rawValue == value) return type;
    }
    return UsageEventType.unknown;
  }
}
