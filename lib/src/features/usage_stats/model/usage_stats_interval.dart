/// Typed representation of Android's UsageStatsManager interval constants.
///
/// Use this enum when calling [UsageStatsManager.getEventStats] to avoid
/// passing magic integers whose meaning is only documented in comments.
///
/// Values correspond 1-to-1 with the Android `UsageStatsManager.INTERVAL_*`
/// and `UsageStatsManager.INTERVAL_BEST` constants.
///
/// **Android only.**
enum UsageStatsInterval {
  /// Let the system pick the most appropriate interval for the time range.
  best(0),

  /// Aggregate data by day.
  daily(1),

  /// Aggregate data by week.
  weekly(2),

  /// Aggregate data by month.
  monthly(3),

  /// Aggregate data by year.
  yearly(4);

  /// The raw integer constant passed to the Android platform.
  final int rawValue;

  const UsageStatsInterval(this.rawValue);

  /// Returns the [UsageStatsInterval] for [rawValue], or [best] if not recognised.
  static UsageStatsInterval fromRawValue(int value) =>
      values.firstWhere((e) => e.rawValue == value, orElse: () => best);
}
