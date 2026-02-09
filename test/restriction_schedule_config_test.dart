import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_schedule.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_schedule_config.dart';

void main() {
  group('RestrictionScheduleConfig', () {
    test('is valid for non-overlapping schedules', () {
      const config = RestrictionScheduleConfig(
        enabled: true,
        schedules: [
          RestrictionSchedule(
            daysOfWeekIso: {1},
            startMinutes: 60,
            endMinutes: 120,
          ),
          RestrictionSchedule(
            daysOfWeekIso: {1},
            startMinutes: 120,
            endMinutes: 180,
          ),
        ],
      );

      expect(config.isValid, isTrue);
    });

    test('rejects overlapping schedules on same day', () {
      const config = RestrictionScheduleConfig(
        enabled: true,
        schedules: [
          RestrictionSchedule(
            daysOfWeekIso: {1},
            startMinutes: 60,
            endMinutes: 180,
          ),
          RestrictionSchedule(
            daysOfWeekIso: {1},
            startMinutes: 120,
            endMinutes: 240,
          ),
        ],
      );

      expect(config.isValid, isFalse);
    });

    test('rejects overlap when overnight spills into next day', () {
      const config = RestrictionScheduleConfig(
        enabled: true,
        schedules: [
          RestrictionSchedule(
            daysOfWeekIso: {1},
            startMinutes: 1380,
            endMinutes: 120,
          ),
          RestrictionSchedule(
            daysOfWeekIso: {2},
            startMinutes: 60,
            endMinutes: 180,
          ),
        ],
      );

      expect(config.isValid, isFalse);
    });
  });
}
