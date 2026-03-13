/// Constants shared between Dart and native host platforms.
///
/// Some constants here are only consumed by native code (Kotlin/Swift) but are
/// mirrored in Dart so the contract is visible from a single source file.
class PlatformConstants {
  PlatformConstants._();

  /// Maximum pause duration that can be reliably scheduled (24 h).
  /// Used by native alarm/monitor scheduling; mirrored here for reference.
  static const int maxReliablePauseDurationMs = 24 * 60 * 60 * 1000;

  /// Default page size when polling pending lifecycle events.
  static const int defaultLifecycleEventsLimit = 200;

  /// Hard cap on the native lifecycle-event queue before oldest entries are
  /// pruned. Used by native stores; mirrored here for reference.
  static const int maxLifecycleEvents = 10000;
}
