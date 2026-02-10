import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/app_restriction_platform.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/restrictions_method_channel.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_modes_config.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_session.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/shield_configuration.dart';

/// Manages app blocking and restriction functionality.
class AppRestrictionManager {
  final AppRestrictionPlatform _platform;

  AppRestrictionManager({AppRestrictionPlatform? platform})
    : _platform = platform ?? RestrictionsMethodChannel();

  /// Configures the appearance of the blocking shield.
  Future<void> configureShield(ShieldConfiguration configuration) {
    return _platform.configureShield(configuration).throwTypedPauzaError();
  }

  /// Upserts one mode.
  Future<void> upsertMode(RestrictionMode mode) {
    return _platform.upsertMode(mode).throwTypedPauzaError();
  }

  /// Removes one mode by [modeId].
  Future<void> removeMode(String modeId) {
    return _platform.removeMode(modeId).throwTypedPauzaError();
  }

  /// Enables or disables schedule-based mode enforcement globally.
  Future<void> setModesEnabled(bool enabled) {
    return _platform.setModesEnabled(enabled).throwTypedPauzaError();
  }

  /// Loads modes configuration.
  Future<RestrictionModesConfig> getModesConfig() {
    return _platform.getModesConfig().throwTypedPauzaError();
  }

  /// Returns whether the restriction session is active right now.
  Future<bool> isRestrictionSessionActiveNow() {
    return _platform.isRestrictionSessionActiveNow().throwTypedPauzaError();
  }

  /// Pauses restriction enforcement for the given [duration].
  Future<void> pauseEnforcement(Duration duration) {
    return _platform.pauseEnforcement(duration).throwTypedPauzaError();
  }

  /// Resumes restriction enforcement immediately.
  Future<void> resumeEnforcement() {
    return _platform.resumeEnforcement().throwTypedPauzaError();
  }

  /// Starts a manual mode session with [modeId].
  Future<void> startModeSession(String modeId) {
    return _platform.startModeSession(modeId).throwTypedPauzaError();
  }

  /// Upserts [mode] and starts it as the active manual session.
  ///
  /// This is the recommended entrypoint for manual starts of non-scheduled
  /// modes, because native storage keeps only enforceable scheduled modes.
  Future<void> startManualModeSession(RestrictionMode mode) async {
    await upsertMode(mode);
    await startModeSession(mode.modeId);
  }

  /// Ends the current manual mode session.
  Future<void> endModeSession() {
    return _platform.endModeSession().throwTypedPauzaError();
  }

  /// Returns the current restriction session snapshot.
  Future<RestrictionSession> getRestrictionSession() {
    return _platform.getRestrictionSession().throwTypedPauzaError();
  }
}
