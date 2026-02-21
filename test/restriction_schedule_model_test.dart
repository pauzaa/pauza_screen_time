import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_schedule.dart';

void main() {
  group('RestrictionSchedule.fromMap', () {
    test('parses valid payload', () {
      final map = <String, dynamic>{
        'daysOfWeekIso': [1, 3, 5],
        'startMinutes': 480,
        'endMinutes': 960,
      };
      final schedule = RestrictionSchedule.fromMap(map);
      expect(schedule.daysOfWeekIso, {1, 3, 5});
      expect(schedule.startMinutes, 480);
      expect(schedule.endMinutes, 960);
    });

    test('throws ArgumentError on empty daysOfWeekIso', () {
      final map = <String, dynamic>{'daysOfWeekIso': <int>[], 'startMinutes': 480, 'endMinutes': 960};
      expect(() => RestrictionSchedule.fromMap(map), throwsArgumentError);
    });

    test('throws ArgumentError on missing startMinutes', () {
      final map = <String, dynamic>{
        'daysOfWeekIso': [1],
        'endMinutes': 960,
      };
      expect(() => RestrictionSchedule.fromMap(map), throwsArgumentError);
    });

    test('throws ArgumentError on missing endMinutes', () {
      final map = <String, dynamic>{
        'daysOfWeekIso': [1],
        'startMinutes': 480,
      };
      expect(() => RestrictionSchedule.fromMap(map), throwsArgumentError);
    });

    test('throws ArgumentError when startMinutes == endMinutes', () {
      final map = <String, dynamic>{
        'daysOfWeekIso': [1],
        'startMinutes': 480,
        'endMinutes': 480,
      };
      expect(() => RestrictionSchedule.fromMap(map), throwsArgumentError);
    });

    test('throws ArgumentError when startMinutes is out of range', () {
      final map = <String, dynamic>{
        'daysOfWeekIso': [1],
        'startMinutes': -1,
        'endMinutes': 960,
      };
      expect(() => RestrictionSchedule.fromMap(map), throwsArgumentError);
    });

    test('round-trips via toMap', () {
      const original = RestrictionSchedule(daysOfWeekIso: {2, 4}, startMinutes: 540, endMinutes: 1020);
      final restored = RestrictionSchedule.fromMap(original.toMap());
      expect(restored.daysOfWeekIso, original.daysOfWeekIso);
      expect(restored.startMinutes, original.startMinutes);
      expect(restored.endMinutes, original.endMinutes);
    });
  });
}
