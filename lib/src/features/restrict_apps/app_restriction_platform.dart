import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_lifecycle_event.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_modes_config.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_state.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/shield_configuration.dart';

/// Platform interface for app restriction functionality.
abstract class AppRestrictionPlatform extends PlatformInterface {
  AppRestrictionPlatform() : super(token: _token);

  static final Object _token = Object();

  /// Configures the shield appearance for blocked apps.
  Future<void> configureShield(ShieldConfiguration configuration) {
    throw UnimplementedError('configureShield() has not been implemented.');
  }

  /// Upserts one mode.
  Future<void> upsertMode(RestrictionMode mode) {
    throw UnimplementedError('upsertMode() has not been implemented.');
  }

  /// Removes one mode by [modeId].
  Future<void> removeMode(String modeId) {
    throw UnimplementedError('removeMode() has not been implemented.');
  }

  /// Enables or disables schedule-based mode enforcement globally.
  Future<void> setModesEnabled(bool enabled) {
    throw UnimplementedError('setModesEnabled() has not been implemented.');
  }

  /// Returns the currently stored modes config.
  Future<RestrictionModesConfig> getModesConfig() {
    throw UnimplementedError('getModesConfig() has not been implemented.');
  }

  /// Returns whether a restriction session is currently active.
  Future<bool> isRestrictionSessionActiveNow() {
    throw UnimplementedError('isRestrictionSessionActiveNow() has not been implemented.');
  }

  /// Pauses restriction enforcement for [duration].
  Future<void> pauseEnforcement(Duration duration) {
    throw UnimplementedError('pauseEnforcement() has not been implemented.');
  }

  /// Resumes restriction enforcement immediately.
  Future<void> resumeEnforcement() {
    throw UnimplementedError('resumeEnforcement() has not been implemented.');
  }

  /// Starts a restriction session for [mode].
  ///
  /// If [duration] is provided, the manual session auto-ends when it elapses.
  Future<void> startSession(RestrictionMode mode, {Duration? duration}) {
    throw UnimplementedError('startSession() has not been implemented.');
  }

  /// Ends the current active restriction session.
  ///
  /// If [duration] is provided, the current session is ended after it elapses.
  /// If [reason] is provided, it overrides the default lifecycle event reason.
  Future<void> endSession({Duration? duration, RestrictionLifecycleReason? reason}) {
    throw UnimplementedError('endSession() has not been implemented.');
  }

  /// Returns pending lifecycle events ordered oldest-first.
  Future<List<RestrictionLifecycleEvent>> getPendingLifecycleEvents({int limit = 200}) {
    throw UnimplementedError('getPendingLifecycleEvents() has not been implemented.');
  }

  /// Acknowledges lifecycle events through [throughEventId] inclusively.
  Future<void> ackLifecycleEvents({required String throughEventId}) {
    throw UnimplementedError('ackLifecycleEvents() has not been implemented.');
  }

  /// Returns the current restriction session snapshot.
  Future<RestrictionState> getRestrictionSession() {
    throw UnimplementedError('getRestrictionSession() has not been implemented.');
  }
}
