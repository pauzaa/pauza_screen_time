/// App restriction feature method names.
///
/// Keep in sync with native handlers.
class RestrictionsMethodNames {
  const RestrictionsMethodNames._();

  static const String configureShield = 'configureShield';
  static const String upsertMode = 'upsertMode';
  static const String removeMode = 'removeMode';
  static const String setScheduleEnforcementEnabled = 'setScheduleEnforcementEnabled';
  static const String getModesConfig = 'getModesConfig';
  static const String isRestrictionSessionActiveNow = 'isRestrictionSessionActiveNow';
  static const String pauseEnforcement = 'pauseEnforcement';
  static const String resumeEnforcement = 'resumeEnforcement';
  static const String startSession = 'startSession';
  static const String endSession = 'endSession';
  static const String getPendingLifecycleEvents = 'getPendingLifecycleEvents';
  static const String ackLifecycleEvents = 'ackLifecycleEvents';
  static const String getRestrictionSession = 'getRestrictionSession';
}
