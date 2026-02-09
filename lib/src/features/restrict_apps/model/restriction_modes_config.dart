import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_schedule.dart';

/// Restriction modes config used for mode-based enforcement.
class RestrictionModesConfig {
  const RestrictionModesConfig({required this.enabled, required this.modes});

  final bool enabled;
  final List<RestrictionMode> modes;

  factory RestrictionModesConfig.fromMap(Map<String, dynamic> map) {
    final enabled = map['enabled'] as bool? ?? false;
    final modes = switch (map['modes']) {
      final List<dynamic> value =>
        value
            .whereType<Map<dynamic, dynamic>>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .map(RestrictionMode.fromMap)
            .toList(),
      _ => const <RestrictionMode>[],
    };

    return RestrictionModesConfig(enabled: enabled, modes: modes);
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enabled': enabled,
      'modes': modes.map((mode) => mode.toMap()).toList(),
    };
  }

  bool get isValid {
    if (modes.any((mode) => !mode.isValid)) {
      return false;
    }
    return _validateNoOverlap(
      modes
          .where((mode) => mode.isEnabled && mode.schedule != null)
          .map((mode) => mode.schedule!)
          .toList(),
    );
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
