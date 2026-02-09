import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_schedule.dart';

/// One restriction mode with optional schedule and blocked app identifiers.
class RestrictionMode {
  const RestrictionMode({
    required this.modeId,
    required this.isEnabled,
    required this.blockedAppIds,
    this.schedule,
  });

  final String modeId;
  final bool isEnabled;
  final RestrictionSchedule? schedule;
  final List<AppIdentifier> blockedAppIds;

  factory RestrictionMode.fromMap(Map<String, dynamic> map) {
    final modeId = map['modeId'] as String? ?? '';
    final isEnabled = map['isEnabled'] as bool? ?? true;
    final schedule = switch (map['schedule']) {
      final Map<dynamic, dynamic> value => RestrictionSchedule.fromMap(
        Map<String, dynamic>.from(value),
      ),
      _ => null,
    };
    final blockedAppIds = switch (map['blockedAppIds']) {
      final List<dynamic> value =>
        value.whereType<String>().map(AppIdentifier.new).toList(),
      _ => const <AppIdentifier>[],
    };

    return RestrictionMode(
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
      'schedule': schedule?.toMap(),
      'blockedAppIds': blockedAppIds
          .map((identifier) => identifier.value)
          .toList(),
    };
  }

  bool get isValid {
    final trimmedModeId = modeId.trim();
    if (trimmedModeId.isEmpty) {
      return false;
    }
    if (schedule != null && !schedule!.isValidBasic) {
      return false;
    }
    return blockedAppIds
        .map((identifier) => identifier.value.trim())
        .every((value) => value.isNotEmpty);
  }
}
