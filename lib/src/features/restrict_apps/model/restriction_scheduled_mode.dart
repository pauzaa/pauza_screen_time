import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_schedule.dart';

/// Single scheduled mode entry: one mode maps to one schedule and app ids.
class RestrictionScheduledMode {
  const RestrictionScheduledMode({
    required this.modeId,
    required this.isEnabled,
    required this.schedule,
    required this.blockedAppIds,
  });

  final String modeId;
  final bool isEnabled;
  final RestrictionSchedule schedule;
  final List<AppIdentifier> blockedAppIds;

  factory RestrictionScheduledMode.fromMap(Map<String, dynamic> map) {
    final modeId = map['modeId'] as String? ?? '';
    final isEnabled = map['isEnabled'] as bool? ?? true;
    final schedule = switch (map['schedule']) {
      final Map<dynamic, dynamic> value => RestrictionSchedule.fromMap(
        Map<String, dynamic>.from(value),
      ),
      _ => const RestrictionSchedule(
        daysOfWeekIso: <int>{},
        startMinutes: -1,
        endMinutes: -1,
      ),
    };
    final blockedAppIds = switch (map['blockedAppIds']) {
      final List<dynamic> value =>
        value.whereType<String>().map(AppIdentifier.new).toList(),
      _ => const <AppIdentifier>[],
    };

    return RestrictionScheduledMode(
      modeId: modeId,
      isEnabled: isEnabled,
      schedule: schedule,
      blockedAppIds: blockedAppIds,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'modeId': modeId,
      'isEnabled': isEnabled,
      'schedule': schedule.toMap(),
      'blockedAppIds': blockedAppIds
          .map((identifier) => identifier.value)
          .toList(),
    };
  }

  bool get isValid {
    return modeId.trim().isNotEmpty &&
        schedule.isValidBasic &&
        blockedAppIds
            .map((identifier) => identifier.value.trim())
            .every((value) => value.isNotEmpty);
  }
}
