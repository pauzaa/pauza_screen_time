/// Typed representation of Android's app standby bucket values.
///
/// The system assigns each app to a standby bucket that determines how
/// aggressively background work and alarms are restricted.
///
/// **Android 9 (API 28) and above only.**
enum AppStandbyBucket {
  /// App is actively in use. No restrictions.
  active(10),

  /// App has been used recently. Light restrictions.
  workingSet(20),

  /// App is used regularly but not daily. Moderate restrictions.
  frequent(30),

  /// App was last used weeks ago. Heavy restrictions.
  rare(40),

  /// App was never used or used only briefly. Strictest restrictions (API 30+).
  restricted(45),

  /// Unrecognised value returned by the platform — should not normally occur.
  unknown(-1);

  /// The raw integer value returned by the Android platform.
  final int rawValue;

  const AppStandbyBucket(this.rawValue);

  /// Returns the [AppStandbyBucket] for [rawValue], or [unknown] if not recognised.
  static AppStandbyBucket fromRawValue(int value) =>
      values.firstWhere((e) => e.rawValue == value, orElse: () => unknown);
}
