import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode_source.dart';

/// Snapshot of the current restriction session state.
class RestrictionSession {
  const RestrictionSession({
    required this.isScheduleEnabled,
    required this.isInScheduleNow,
    required this.pausedUntil,
    required this.activeMode,
    required this.activeModeSource,
  });

  /// Whether schedule-based restriction session is enabled.
  final bool isScheduleEnabled;

  /// Whether current time falls inside any configured schedule window.
  final bool isInScheduleNow;

  /// When pause ends, if paused.
  final DateTime? pausedUntil;

  /// Active mode when resolved.
  final RestrictionMode? activeMode;

  /// Source that selected the active mode.
  final RestrictionModeSource activeModeSource;

  /// Whether restrictions are currently considered active.
  bool get isActiveNow => activeMode != null;

  /// Whether restriction enforcement is currently paused.
  bool get isPausedNow => pausedUntil != null;

  /// Parses session payload from platform channels.
  factory RestrictionSession.fromMap(Map<String, dynamic> map) {
    final isScheduleEnabled = map['isScheduleEnabled'] as bool? ?? false;
    final isInScheduleNow = map['isInScheduleNow'] as bool? ?? false;
    final pausedUntilEpochMs = switch (map['pausedUntilEpochMs']) {
      final int value => value,
      final num value => value.toInt(),
      _ => null,
    };
    final activeMode = switch (map['activeMode']) {
      final Map<dynamic, dynamic> value => RestrictionMode.fromMap(
        Map<String, dynamic>.from(value),
      ),
      _ => null,
    };

    final sourceRaw = map['activeModeSource'] as String? ?? 'none';
    final activeModeSource = switch (sourceRaw) {
      'none' => RestrictionModeSource.none,
      'manual' => RestrictionModeSource.manual,
      'schedule' => RestrictionModeSource.schedule,
      _ => throw ArgumentError.value(
        sourceRaw,
        'activeModeSource',
        'Unsupported mode source',
      ),
    };

    return RestrictionSession(
      isScheduleEnabled: isScheduleEnabled,
      isInScheduleNow: isInScheduleNow,
      pausedUntil: pausedUntilEpochMs == null || pausedUntilEpochMs <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(pausedUntilEpochMs),
      activeMode: activeMode,
      activeModeSource: activeModeSource,
    );
  }

  /// Whether the currently active mode source is manual.
  bool get isManuallyEnabled =>
      activeModeSource == RestrictionModeSource.manual;
}
