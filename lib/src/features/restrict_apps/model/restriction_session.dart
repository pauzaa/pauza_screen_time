import 'package:pauza_screen_time/src/core/app_identifier.dart';

/// Snapshot of the current restriction session state.
class RestrictionSession {
  const RestrictionSession({
    required this.isActiveNow,
    required this.isPausedNow,
    required this.isManuallyEnabled,
    required this.isScheduleEnabled,
    required this.isInScheduleNow,
    required this.pausedUntil,
    required this.restrictedApps,
  });

  /// Whether restrictions are currently considered active.
  final bool isActiveNow;

  /// Whether restriction enforcement is currently paused.
  final bool isPausedNow;

  /// Whether manual restriction session is enabled.
  final bool isManuallyEnabled;

  /// Whether schedule-based restriction session is enabled.
  final bool isScheduleEnabled;

  /// Whether current time falls inside any configured schedule window.
  final bool isInScheduleNow;

  /// When pause ends, if paused.
  final DateTime? pausedUntil;

  /// Current restricted app identifiers.
  final List<AppIdentifier> restrictedApps;

  /// Parses session payload from platform channels.
  factory RestrictionSession.fromMap(Map<String, dynamic> map) {
    final isActiveNow = map['isActiveNow'] as bool? ?? false;
    final isPausedNow = map['isPausedNow'] as bool? ?? false;
    final isManuallyEnabled = map['isManuallyEnabled'] as bool? ?? true;
    final isScheduleEnabled = map['isScheduleEnabled'] as bool? ?? false;
    final isInScheduleNow = map['isInScheduleNow'] as bool? ?? false;
    final pausedUntilEpochMs = switch (map['pausedUntilEpochMs']) {
      final int value => value,
      final num value => value.toInt(),
      _ => null,
    };
    final rawRestrictedApps = map['restrictedApps'];
    final restrictedApps = switch (rawRestrictedApps) {
      final List<dynamic> values =>
        values.whereType<String>().map(AppIdentifier.new).toList(),
      _ => const <AppIdentifier>[],
    };

    return RestrictionSession(
      isActiveNow: isActiveNow,
      isPausedNow: isPausedNow,
      isManuallyEnabled: isManuallyEnabled,
      isScheduleEnabled: isScheduleEnabled,
      isInScheduleNow: isInScheduleNow,
      pausedUntil: pausedUntilEpochMs == null || pausedUntilEpochMs <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(pausedUntilEpochMs),
      restrictedApps: restrictedApps,
    );
  }
}
