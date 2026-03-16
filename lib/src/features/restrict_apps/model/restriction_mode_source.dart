/// Source that selected an active restriction mode.
enum RestrictionModeSource {
  none('none'),
  manual('manual'),
  schedule('schedule'),
  unknown('unknown');

  const RestrictionModeSource(this.wireValue);

  /// The string value transmitted over the method channel.
  final String wireValue;

  /// Parses from the wire string representation.
  /// Returns [unknown] for unrecognised values (forward compatibility).
  static RestrictionModeSource fromWire(String raw) => switch (raw) {
    'none' => RestrictionModeSource.none,
    'manual' => RestrictionModeSource.manual,
    'schedule' => RestrictionModeSource.schedule,
    _ => RestrictionModeSource.unknown,
  };
}
