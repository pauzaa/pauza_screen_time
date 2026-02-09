import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_modes_config.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_schedule.dart';

void main() {
  group('RestrictionModesConfig', () {
    test('is valid for non-overlapping scheduled modes', () {
      const config = RestrictionModesConfig(
        enabled: true,
        modes: [
          RestrictionMode(
            modeId: 'mode_a',
            isEnabled: true,
            schedule: RestrictionSchedule(
              daysOfWeekIso: {1},
              startMinutes: 60,
              endMinutes: 120,
            ),
            blockedAppIds: [AppIdentifier('com.example.a')],
          ),
          RestrictionMode(
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
      const config = RestrictionModesConfig(
        enabled: true,
        modes: [
          RestrictionMode(
            modeId: 'mode_a',
            isEnabled: true,
            schedule: RestrictionSchedule(
              daysOfWeekIso: {1},
              startMinutes: 60,
              endMinutes: 180,
            ),
            blockedAppIds: [AppIdentifier('com.example.a')],
          ),
          RestrictionMode(
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

    test('allows non-scheduled mode alongside scheduled mode', () {
      const config = RestrictionModesConfig(
        enabled: true,
        modes: [
          RestrictionMode(
            modeId: 'manual_only',
            isEnabled: true,
            blockedAppIds: [AppIdentifier('com.example.manual')],
          ),
          RestrictionMode(
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

      expect(config.isValid, isTrue);
    });

    test('serializes and parses mode config', () {
      const config = RestrictionModesConfig(
        enabled: true,
        modes: [
          RestrictionMode(
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

      final roundTrip = RestrictionModesConfig.fromMap(config.toMap());
      expect(roundTrip.enabled, isTrue);
      expect(roundTrip.modes, hasLength(1));
      expect(roundTrip.modes.first.modeId, 'focus');
      expect(
        roundTrip.modes.first.blockedAppIds.first.value,
        'com.example.app',
      );
    });
  });
}
