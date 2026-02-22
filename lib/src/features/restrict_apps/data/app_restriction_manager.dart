import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/app_restriction_platform.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/restrictions_method_channel.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_lifecycle_event.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_modes_config.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_state.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/shield_configuration.dart';

/// Manages app blocking and restriction functionality.
class AppRestrictionManager {
  final AppRestrictionPlatform _platform;

  AppRestrictionManager({AppRestrictionPlatform? platform}) : _platform = platform ?? RestrictionsMethodChannel();

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

  /// Starts a session using [mode].
  ///
  /// If [duration] is provided, the manual session auto-ends when it elapses.
  Future<void> startSession(RestrictionMode mode, {Duration? duration}) {
    return _platform.startSession(mode, duration: duration).throwTypedPauzaError();
  }

  /// Ends the current active session.
  Future<void> endSession() {
    return _platform.endSession().throwTypedPauzaError();
  }

  /// Returns pending lifecycle events ordered oldest-first.
  Future<List<RestrictionLifecycleEvent>> getPendingLifecycleEvents({int limit = 200}) {
    return _platform.getPendingLifecycleEvents(limit: limit).throwTypedPauzaError();
  }

  /// Acknowledges lifecycle events through [throughEventId] inclusively.
  Future<void> ackLifecycleEvents({required String throughEventId}) {
    return _platform.ackLifecycleEvents(throughEventId: throughEventId).throwTypedPauzaError();
  }

  /// Returns the current restriction session snapshot.
  Future<RestrictionState> getRestrictionSession() {
    return _platform.getRestrictionSession().throwTypedPauzaError();
  }
}
