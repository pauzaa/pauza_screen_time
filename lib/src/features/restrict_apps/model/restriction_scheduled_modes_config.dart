import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_schedule_config.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_scheduled_mode.dart';

/// Scheduled modes config used for one-mode-per-schedule enforcement.
class RestrictionScheduledModesConfig {
  const RestrictionScheduledModesConfig({
    required this.enabled,
    required this.scheduledModes,
  });

  final bool enabled;
  final List<RestrictionScheduledMode> scheduledModes;

  factory RestrictionScheduledModesConfig.fromMap(Map<String, dynamic> map) {
    final enabled = map['enabled'] as bool? ?? false;
    final scheduledModes = switch (map['scheduledModes']) {
      final List<dynamic> value =>
        value
            .whereType<Map<dynamic, dynamic>>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .map(RestrictionScheduledMode.fromMap)
            .toList(),
      _ => const <RestrictionScheduledMode>[],
    };

    return RestrictionScheduledModesConfig(
      enabled: enabled,
      scheduledModes: scheduledModes,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enabled': enabled,
      'scheduledModes': scheduledModes.map((mode) => mode.toMap()).toList(),
    };
  }

  bool get isValid {
    if (scheduledModes.any((mode) => !mode.isValid)) {
      return false;
    }
    final scheduleConfig = RestrictionScheduleConfig(
      enabled: enabled,
      schedules: scheduledModes
          .where((mode) => mode.isEnabled)
          .map((mode) => mode.schedule)
          .toList(),
    );
    return scheduleConfig.isValid;
  }
}
