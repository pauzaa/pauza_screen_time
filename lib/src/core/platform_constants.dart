/// Constants shared between Dart and native host platforms.
class PlatformConstants {
  PlatformConstants._();

  static const int maxReliablePauseDurationMs = 24 * 60 * 60 * 1000;
  static const int defaultLifecycleEventsLimit = 200;
  static const int maxLifecycleEvents = 10000;
}
