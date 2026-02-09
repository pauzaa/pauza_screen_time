import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_scheduled_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_scheduled_modes_config.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_session.dart';

/// Platform interface for app restriction functionality.
abstract class AppRestrictionPlatform extends PlatformInterface {
  AppRestrictionPlatform() : super(token: _token);

  static final Object _token = Object();

  /// Configures the shield appearance for blocked apps.
  Future<void> configureShield(Map<String, dynamic> configuration) {
    throw UnimplementedError('configureShield() has not been implemented.');
  }

  /// Sets the list of apps to be restricted.
  ///
  /// Returns the list of identifiers that were successfully applied on the
  /// native side (deduplicated, input-order-preserving).
  Future<List<AppIdentifier>> setRestrictedApps(
    List<AppIdentifier> identifiers,
  ) {
    throw UnimplementedError('setRestrictedApps() has not been implemented.');
  }

  /// Adds a single app to the restricted set.
  ///
  /// Returns `true` if the restricted set changed, `false` if it was a no-op.
  Future<bool> addRestrictedApp(AppIdentifier identifier) {
    throw UnimplementedError('addRestrictedApp() has not been implemented.');
  }

  /// Removes restriction from a specific app.
  ///
  /// Returns `true` if the restricted set changed, `false` if it was a no-op.
  Future<bool> removeRestriction(AppIdentifier identifier) {
    throw UnimplementedError('removeRestriction() has not been implemented.');
  }

  /// Checks if an app is currently restricted.
  Future<bool> isRestricted(AppIdentifier identifier) {
    throw UnimplementedError('isRestricted() has not been implemented.');
  }

  /// Removes all app restrictions.
  Future<void> removeAllRestrictions() {
    throw UnimplementedError(
      'removeAllRestrictions() has not been implemented.',
    );
  }

  /// Returns the list of currently restricted package IDs.
  Future<List<AppIdentifier>> getRestrictedApps() {
    throw UnimplementedError('getRestrictedApps() has not been implemented.');
  }

  /// Returns whether a restriction session is currently active.
  Future<bool> isRestrictionSessionActiveNow() {
    throw UnimplementedError(
      'isRestrictionSessionActiveNow() has not been implemented.',
    );
  }

  /// Returns whether a restriction session is configured.
  Future<bool> isRestrictionSessionConfigured() {
    throw UnimplementedError(
      'isRestrictionSessionConfigured() has not been implemented.',
    );
  }

  /// Pauses restriction enforcement for [duration].
  Future<void> pauseEnforcement(Duration duration) {
    throw UnimplementedError('pauseEnforcement() has not been implemented.');
  }

  /// Resumes restriction enforcement immediately.
  Future<void> resumeEnforcement() {
    throw UnimplementedError('resumeEnforcement() has not been implemented.');
  }

  /// Starts a manual restriction session.
  Future<void> startRestrictionSession() {
    throw UnimplementedError(
      'startRestrictionSession() has not been implemented.',
    );
  }

  /// Ends a manual restriction session.
  Future<void> endRestrictionSession() {
    throw UnimplementedError(
      'endRestrictionSession() has not been implemented.',
    );
  }

  /// Returns the current restriction session snapshot.
  Future<RestrictionSession> getRestrictionSession() {
    throw UnimplementedError(
      'getRestrictionSession() has not been implemented.',
    );
  }

  /// Upserts one mode with a single schedule and blocked identifiers.
  Future<void> upsertScheduledMode(RestrictionScheduledMode mode) {
    throw UnimplementedError('upsertScheduledMode() has not been implemented.');
  }

  /// Removes one scheduled mode by [modeId].
  Future<void> removeScheduledMode(String modeId) {
    throw UnimplementedError('removeScheduledMode() has not been implemented.');
  }

  /// Enables or disables schedule-based mode enforcement globally.
  Future<void> setScheduledModesEnabled(bool enabled) {
    throw UnimplementedError(
      'setScheduledModesEnabled() has not been implemented.',
    );
  }

  /// Returns the currently stored scheduled modes config.
  Future<RestrictionScheduledModesConfig> getScheduledModesConfig() {
    throw UnimplementedError(
      'getScheduledModesConfig() has not been implemented.',
    );
  }
}
