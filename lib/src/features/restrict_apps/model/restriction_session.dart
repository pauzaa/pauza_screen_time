import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode_source.dart';

/// Snapshot of the current restriction session state.
class RestrictionSession {
  const RestrictionSession({
    required this.isActiveNow,
    required this.isPausedNow,
    required this.isScheduleEnabled,
    required this.isInScheduleNow,
    required this.pausedUntil,
    required this.restrictedApps,
    required this.activeModeId,
    required this.activeModeSource,
  });

  /// Whether restrictions are currently considered active.
  final bool isActiveNow;

  /// Whether restriction enforcement is currently paused.
  final bool isPausedNow;

  /// Whether schedule-based restriction session is enabled.
  final bool isScheduleEnabled;

  /// Whether current time falls inside any configured schedule window.
  final bool isInScheduleNow;

  /// When pause ends, if paused.
  final DateTime? pausedUntil;

  /// Current restricted app identifiers.
  final List<AppIdentifier> restrictedApps;

  /// Active mode identifier when resolved.
  final String? activeModeId;

  /// Source that selected the active mode.
  final RestrictionModeSource activeModeSource;

  /// Parses session payload from platform channels.
  factory RestrictionSession.fromMap(Map<String, dynamic> map) {
    final isActiveNow = map['isActiveNow'] as bool? ?? false;
    final isPausedNow = map['isPausedNow'] as bool? ?? false;
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

    final activeModeId = (map['activeModeId'] as String?)?.trim();
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
      isActiveNow: isActiveNow,
      isPausedNow: isPausedNow,
      isScheduleEnabled: isScheduleEnabled,
      isInScheduleNow: isInScheduleNow,
      pausedUntil: pausedUntilEpochMs == null || pausedUntilEpochMs <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(pausedUntilEpochMs),
      restrictedApps: restrictedApps,
      activeModeId: (activeModeId == null || activeModeId.isEmpty)
          ? null
          : activeModeId,
      activeModeSource: activeModeSource,
    );
  }

  /// Whether the currently active mode source is manual.
  bool get isManuallyEnabled =>
      activeModeSource == RestrictionModeSource.manual;
}
