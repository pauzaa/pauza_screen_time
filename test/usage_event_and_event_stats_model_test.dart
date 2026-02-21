import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/event_stats.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/usage_event.dart';

void main() {
  group('UsageEventType', () {
    test('fromRawValue returns correct enum for known values', () {
      expect(UsageEventType.fromRawValue(1), UsageEventType.activityResumed);
      expect(UsageEventType.fromRawValue(2), UsageEventType.activityPaused);
      expect(UsageEventType.fromRawValue(23), UsageEventType.activityStopped);
      expect(UsageEventType.fromRawValue(5), UsageEventType.configurationChange);
      expect(UsageEventType.fromRawValue(7), UsageEventType.userInteraction);
      expect(UsageEventType.fromRawValue(8), UsageEventType.shortcutInvocation);
      expect(UsageEventType.fromRawValue(15), UsageEventType.screenInteractive);
      expect(UsageEventType.fromRawValue(16), UsageEventType.screenNonInteractive);
      expect(UsageEventType.fromRawValue(17), UsageEventType.keyguardShown);
      expect(UsageEventType.fromRawValue(18), UsageEventType.keyguardHidden);
      expect(UsageEventType.fromRawValue(19), UsageEventType.foregroundServiceStart);
      expect(UsageEventType.fromRawValue(20), UsageEventType.foregroundServiceStop);
      expect(UsageEventType.fromRawValue(26), UsageEventType.deviceShutdown);
      expect(UsageEventType.fromRawValue(27), UsageEventType.deviceStartup);
      expect(UsageEventType.fromRawValue(11), UsageEventType.standbyBucketChanged);
    });

    test('fromRawValue returns unknown for unrecognised values', () {
      expect(UsageEventType.fromRawValue(999), UsageEventType.unknown);
      expect(UsageEventType.fromRawValue(0), UsageEventType.unknown);
      expect(UsageEventType.fromRawValue(-99), UsageEventType.unknown);
    });

    test('rawValue round-trips correctly', () {
      for (final type in UsageEventType.values) {
        if (type == UsageEventType.unknown) continue;
        expect(UsageEventType.fromRawValue(type.rawValue), type);
      }
    });
  });

  group('UsageEvent.fromMap', () {
    test('deserialises a complete app event correctly', () {
      final map = {
        'timestampMs': 1700000000000,
        'packageName': 'com.example.app',
        'className': 'com.example.app.MainActivity',
        'eventType': 1, // activityResumed
      };

      final event = UsageEvent.fromMap(map);

      expect(event.timestamp, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(event.packageName, 'com.example.app');
      expect(event.className, 'com.example.app.MainActivity');
      expect(event.eventType, UsageEventType.activityResumed);
    });

    test('handles null className for system-level events', () {
      final map = {
        'timestampMs': 1700000001000,
        'packageName': 'android',
        'className': null,
        'eventType': 15, // screenInteractive
      };

      final event = UsageEvent.fromMap(map);

      expect(event.className, isNull);
      expect(event.eventType, UsageEventType.screenInteractive);
    });

    test('maps unknown event type to UsageEventType.unknown', () {
      final map = {'timestampMs': 1700000002000, 'packageName': 'android', 'className': null, 'eventType': 9999};

      final event = UsageEvent.fromMap(map);
      expect(event.eventType, UsageEventType.unknown);
    });
  });

  group('UsageEvent.toMap round-trip', () {
    test('toMap is the inverse of fromMap for an app event', () {
      const originalMap = {
        'timestampMs': 1700000000000,
        'packageName': 'com.example.app',
        'className': 'com.example.app.MainActivity',
        'eventType': 1,
      };

      final event = UsageEvent.fromMap(originalMap);
      final roundTripped = event.toMap();

      expect(roundTripped['timestampMs'], originalMap['timestampMs']);
      expect(roundTripped['packageName'], originalMap['packageName']);
      expect(roundTripped['className'], originalMap['className']);
      expect(roundTripped['eventType'], originalMap['eventType']);
    });

    test('toMap preserves null className for system events', () {
      const map = {'timestampMs': 1700000001000, 'packageName': 'android', 'className': null, 'eventType': 15};

      final event = UsageEvent.fromMap(map);
      expect(event.toMap()['className'], isNull);
    });
  });

  group('DeviceEventStats.fromMap', () {
    test('deserialises a screen interactive stat correctly', () {
      final map = {
        'eventType': 15, // screenInteractive
        'count': 42,
        'totalTimeMs': 3600000, // 1 hour
        'firstTimestampMs': 1700000000000,
        'lastTimestampMs': 1700086400000,
        'lastEventTimeMs': 1700080000000,
      };

      final stats = DeviceEventStats.fromMap(map);

      expect(stats.eventType, UsageEventType.screenInteractive);
      expect(stats.count, 42);
      expect(stats.totalTime, const Duration(hours: 1));
      expect(stats.firstTimestamp, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(stats.lastTimestamp, DateTime.fromMillisecondsSinceEpoch(1700086400000));
      expect(stats.lastEventTime, DateTime.fromMillisecondsSinceEpoch(1700080000000));
    });

    test('deserialises a keyguard hidden (unlock) stat correctly', () {
      final map = {
        'eventType': 18, // keyguardHidden
        'count': 78,
        'totalTimeMs': 0,
        'firstTimestampMs': 1700000000000,
        'lastTimestampMs': 1700086400000,
        'lastEventTimeMs': 1700082000000,
      };

      final stats = DeviceEventStats.fromMap(map);

      expect(stats.eventType, UsageEventType.keyguardHidden);
      expect(stats.count, 78);
      expect(stats.totalTime, Duration.zero);
    });
  });

  group('DeviceEventStats.toMap round-trip', () {
    test('toMap is the inverse of fromMap', () {
      const originalMap = {
        'eventType': 15,
        'count': 42,
        'totalTimeMs': 3600000,
        'firstTimestampMs': 1700000000000,
        'lastTimestampMs': 1700086400000,
        'lastEventTimeMs': 1700080000000,
      };

      final stats = DeviceEventStats.fromMap(originalMap);
      final roundTripped = stats.toMap();

      expect(roundTripped['eventType'], originalMap['eventType']);
      expect(roundTripped['count'], originalMap['count']);
      expect(roundTripped['totalTimeMs'], originalMap['totalTimeMs']);
      expect(roundTripped['firstTimestampMs'], originalMap['firstTimestampMs']);
      expect(roundTripped['lastTimestampMs'], originalMap['lastTimestampMs']);
      expect(roundTripped['lastEventTimeMs'], originalMap['lastEventTimeMs']);
    });
  });
}
