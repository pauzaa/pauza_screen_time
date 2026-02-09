import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_schedule.dart';

/// Full schedule configuration for automatic restriction enforcement.
class RestrictionScheduleConfig {
  const RestrictionScheduleConfig({
    required this.enabled,
    required this.schedules,
  });

  final bool enabled;
  final List<RestrictionSchedule> schedules;

  factory RestrictionScheduleConfig.fromMap(Map<String, dynamic> map) {
    final enabled = map['enabled'] as bool? ?? false;
    final schedules = switch (map['schedules']) {
      final List<dynamic> values =>
        values
            .whereType<Map<dynamic, dynamic>>()
            .map((value) => Map<String, dynamic>.from(value))
            .map(RestrictionSchedule.fromMap)
            .toList(),
      _ => const <RestrictionSchedule>[],
    };
    return RestrictionScheduleConfig(enabled: enabled, schedules: schedules);
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enabled': enabled,
      'schedules': schedules.map((schedule) => schedule.toMap()).toList(),
    };
  }

  /// Validates each schedule and checks that no windows overlap.
  ///
  /// Overlaps are evaluated per weekday after splitting overnight windows.
  bool get isValid {
    if (schedules.any((schedule) => !schedule.isValidBasic)) {
      return false;
    }
    return _validateNoOverlap(schedules);
  }

  static bool _validateNoOverlap(List<RestrictionSchedule> schedules) {
    final byDay = <int, List<_Window>>{};
    for (final schedule in schedules) {
      for (final day in schedule.daysOfWeekIso) {
        final dayWindows = byDay.putIfAbsent(day, () => <_Window>[]);
        if (schedule.endMinutes > schedule.startMinutes) {
          dayWindows.add(
            _Window(start: schedule.startMinutes, end: schedule.endMinutes),
          );
        } else {
          dayWindows.add(
            _Window(start: schedule.startMinutes, end: _minutesPerDay),
          );
          final nextDay = day == 7 ? 1 : day + 1;
          final nextDayWindows = byDay.putIfAbsent(nextDay, () => <_Window>[]);
          nextDayWindows.add(_Window(start: 0, end: schedule.endMinutes));
        }
      }
    }

    for (final windows in byDay.values) {
      windows.sort((left, right) => left.start.compareTo(right.start));
      _Window? previous;
      for (final current in windows) {
        if (previous != null && current.start < previous.end) {
          return false;
        }
        previous = current;
      }
    }
    return true;
  }

  static const int _minutesPerDay = 24 * 60;
}

class _Window {
  const _Window({required this.start, required this.end});

  final int start;
  final int end;
}
