/// Weekly schedule entry for automatic restriction enforcement.
class RestrictionSchedule {
  const RestrictionSchedule({
    required this.daysOfWeekIso,
    required this.startMinutes,
    required this.endMinutes,
  });

  /// ISO weekdays: Monday=1 .. Sunday=7.
  final Set<int> daysOfWeekIso;

  /// Start time in minutes from midnight (0..1439).
  final int startMinutes;

  /// End time in minutes from midnight (0..1439).
  ///
  /// If `endMinutes <= startMinutes`, the schedule spans midnight.
  final int endMinutes;

  /// Builds a schedule from a method-channel payload.
  factory RestrictionSchedule.fromMap(Map<String, dynamic> map) {
    final days = switch (map['daysOfWeekIso']) {
      final List<dynamic> values =>
        values
            .whereType<num>()
            .map((value) => value.toInt())
            .where((value) => value >= 1 && value <= 7)
            .toSet(),
      _ => <int>{},
    };
    final start = switch (map['startMinutes']) {
      final int value => value,
      final num value => value.toInt(),
      _ => -1,
    };
    final end = switch (map['endMinutes']) {
      final int value => value,
      final num value => value.toInt(),
      _ => -1,
    };

    return RestrictionSchedule(
      daysOfWeekIso: days,
      startMinutes: start,
      endMinutes: end,
    );
  }

  /// Serializes this schedule to method-channel payload.
  Map<String, dynamic> toMap() {
    final sortedDays = daysOfWeekIso.toList()..sort();
    return <String, dynamic>{
      'daysOfWeekIso': sortedDays,
      'startMinutes': startMinutes,
      'endMinutes': endMinutes,
    };
  }

  /// Returns true when all scalar fields are in allowed bounds.
  bool get isValidBasic {
    return daysOfWeekIso.isNotEmpty &&
        daysOfWeekIso.every((day) => day >= 1 && day <= 7) &&
        startMinutes >= 0 &&
        startMinutes < _minutesPerDay &&
        endMinutes >= 0 &&
        endMinutes < _minutesPerDay &&
        startMinutes != endMinutes;
  }

  static const int _minutesPerDay = 24 * 60;
}
