import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_schedule.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_scheduled_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_scheduled_modes_config.dart';

void main() {
  group('RestrictionScheduledModesConfig', () {
    test('is valid for non-overlapping modes', () {
      const config = RestrictionScheduledModesConfig(
        enabled: true,
        scheduledModes: [
          RestrictionScheduledMode(
            modeId: 'mode_a',
            isEnabled: true,
            schedule: RestrictionSchedule(
              daysOfWeekIso: {1},
              startMinutes: 60,
              endMinutes: 120,
            ),
            blockedAppIds: [AppIdentifier('com.example.a')],
          ),
          RestrictionScheduledMode(
            modeId: 'mode_b',
            isEnabled: true,
            schedule: RestrictionSchedule(
              daysOfWeekIso: {1},
              startMinutes: 120,
              endMinutes: 180,
            ),
            blockedAppIds: [AppIdentifier('com.example.b')],
          ),
        ],
      );

      expect(config.isValid, isTrue);
    });

    test('rejects overlapping schedules across modes', () {
      const config = RestrictionScheduledModesConfig(
        enabled: true,
        scheduledModes: [
          RestrictionScheduledMode(
            modeId: 'mode_a',
            isEnabled: true,
            schedule: RestrictionSchedule(
              daysOfWeekIso: {1},
              startMinutes: 60,
              endMinutes: 180,
            ),
            blockedAppIds: [AppIdentifier('com.example.a')],
          ),
          RestrictionScheduledMode(
            modeId: 'mode_b',
            isEnabled: true,
            schedule: RestrictionSchedule(
              daysOfWeekIso: {1},
              startMinutes: 120,
              endMinutes: 240,
            ),
            blockedAppIds: [AppIdentifier('com.example.b')],
          ),
        ],
      );

      expect(config.isValid, isFalse);
    });

    test('serializes and parses scheduled mode config', () {
      const config = RestrictionScheduledModesConfig(
        enabled: true,
        scheduledModes: [
          RestrictionScheduledMode(
            modeId: 'focus',
            isEnabled: true,
            schedule: RestrictionSchedule(
              daysOfWeekIso: {1, 2},
              startMinutes: 9 * 60,
              endMinutes: 10 * 60,
            ),
            blockedAppIds: [AppIdentifier('com.example.app')],
          ),
        ],
      );

      final roundTrip = RestrictionScheduledModesConfig.fromMap(config.toMap());
      expect(roundTrip.enabled, isTrue);
      expect(roundTrip.scheduledModes, hasLength(1));
      expect(roundTrip.scheduledModes.first.modeId, 'focus');
      expect(
        roundTrip.scheduledModes.first.blockedAppIds.first.value,
        'com.example.app',
      );
    });
  });
}
