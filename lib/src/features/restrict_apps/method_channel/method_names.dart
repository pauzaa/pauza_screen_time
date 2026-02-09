/// App restriction feature method names.
///
/// Keep in sync with native handlers.
class RestrictionsMethodNames {
  const RestrictionsMethodNames._();

  static const String configureShield = 'configureShield';
  static const String setRestrictedApps = 'setRestrictedApps';
  static const String addRestrictedApp = 'addRestrictedApp';
  static const String removeRestriction = 'removeRestriction';
  static const String removeAllRestrictions = 'removeAllRestrictions';
  static const String getRestrictedApps = 'getRestrictedApps';
  static const String isRestricted = 'isRestricted';
  static const String isRestrictionSessionActiveNow =
      'isRestrictionSessionActiveNow';
  static const String isRestrictionSessionConfigured =
      'isRestrictionSessionConfigured';
  static const String pauseEnforcement = 'pauseEnforcement';
  static const String resumeEnforcement = 'resumeEnforcement';
  static const String startRestrictionSession = 'startRestrictionSession';
  static const String endRestrictionSession = 'endRestrictionSession';
  static const String setRestrictionScheduleConfig =
      'setRestrictionScheduleConfig';
  static const String getRestrictionScheduleConfig =
      'getRestrictionScheduleConfig';
  static const String getRestrictionSession = 'getRestrictionSession';
  static const String upsertScheduledMode = 'upsertScheduledMode';
  static const String removeScheduledMode = 'removeScheduledMode';
  static const String setScheduledModesEnabled = 'setScheduledModesEnabled';
  static const String getScheduledModesConfig = 'getScheduledModesConfig';
}
