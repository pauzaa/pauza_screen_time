import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_lifecycle_event.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode_source.dart';

/// Snapshot of the current restriction session state.
class RestrictionState {
  const RestrictionState({
    required this.isScheduleEnabled,
    required this.isInScheduleNow,
    required this.pausedUntil,
    required this.activeMode,
    required this.activeModeSource,
    required this.currentSessionEvents,
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

  /// Lifecycle events persisted for the current active session snapshot.
  final List<RestrictionLifecycleEvent> currentSessionEvents;

  /// Whether restrictions are currently considered active.
  bool get isActiveNow => activeMode != null;

  /// Whether restriction enforcement is currently paused.
  bool get isPausedNow => pausedUntil != null;

  /// Parses session payload from platform channels.
  factory RestrictionState.fromMap(Map<String, dynamic> map) {
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
    final currentSessionEvents = switch (map['currentSessionEvents']) {
      final List<dynamic> values =>
        values
            .map((value) {
              if (value is! Map) {
                throw ArgumentError.value(
                  value,
                  'currentSessionEvents',
                  'Event entries must be maps',
                );
              }
              return RestrictionLifecycleEvent.fromMap(
                Map<String, dynamic>.from(value),
              );
            })
            .toList(growable: false),
      _ => const <RestrictionLifecycleEvent>[],
    };
    final startEventsCount = currentSessionEvents
        .where((event) => event.action == RestrictionLifecycleAction.start)
        .length;
    assert(
      startEventsCount <= 1,
      'currentSessionEvents must contain at most one START event',
    );

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

    return RestrictionState(
      isScheduleEnabled: isScheduleEnabled,
      isInScheduleNow: isInScheduleNow,
      pausedUntil: pausedUntilEpochMs == null || pausedUntilEpochMs <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(pausedUntilEpochMs),
      activeMode: activeMode,
      activeModeSource: activeModeSource,
      currentSessionEvents: currentSessionEvents,
    );
  }

  /// Whether the currently active mode source is manual.
  bool get isManuallyEnabled =>
      activeModeSource == RestrictionModeSource.manual;

  /// Most recent session start timestamp when present in current session events.
  DateTime? get startedAt {
    for (final event in currentSessionEvents) {
      if (event.action == RestrictionLifecycleAction.start) {
        return event.occurredAt;
      }
    }
    return null;
  }

  /// Pause start timestamp for the currently active pause window, if any.
  DateTime? get activePauseStartedAt {
    if (!isPausedNow) {
      return null;
    }
    for (final event in currentSessionEvents.reversed) {
      switch (event.action) {
        case RestrictionLifecycleAction.pause:
          return event.occurredAt;
        case RestrictionLifecycleAction.resume:
        case RestrictionLifecycleAction.end:
          return null;
        case RestrictionLifecycleAction.start:
          continue;
      }
    }
    return null;
  }
}
