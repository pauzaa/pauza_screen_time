/// Source that selected an active restriction mode.
enum RestrictionModeSource {
  none('none'),
  manual('manual'),
  schedule('schedule');

  const RestrictionModeSource(this.wireValue);

  /// The string value transmitted over the method channel.
  final String wireValue;

  /// Parses from the wire string representation.
  /// Throws [ArgumentError] for unknown values.
  static RestrictionModeSource fromWire(String raw) => switch (raw) {
    'none' => RestrictionModeSource.none,
    'manual' => RestrictionModeSource.manual,
    'schedule' => RestrictionModeSource.schedule,
    _ => throw ArgumentError.value(raw, 'activeModeSource', 'Unsupported mode source'),
  };
}
