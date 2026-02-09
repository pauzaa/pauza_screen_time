import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/app_restriction_platform.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/restrictions_method_channel.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_scheduled_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_scheduled_modes_config.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_session.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/shield_configuration.dart';

/// Manages app blocking and restriction functionality.
class AppRestrictionManager {
  final AppRestrictionPlatform _platform;

  AppRestrictionManager({AppRestrictionPlatform? platform})
    : _platform = platform ?? RestrictionsMethodChannel();

  // ============================================================
  // Shield Configuration
  // ============================================================

  /// Configures the appearance of the blocking shield.
  ///
  /// Must be called before setting restrictions to define how
  /// the shield will appear when a restricted app is launched.
  Future<void> configureShield(ShieldConfiguration configuration) {
    return _platform
        .configureShield(configuration.toMap())
        .throwTypedPauzaError();
  }

  // ============================================================
  // Restriction Management
  // ============================================================

  /// Restricts the specified apps by opaque identifiers.
  ///
  /// When a restricted app is launched, the configured shield will be displayed.
  ///
  /// Returns the list of identifiers that were successfully applied on the
  /// native side (deduplicated, input-order-preserving).
  ///
  /// [identifiers] - List of identifiers:
  /// - Android: package names.
  /// - iOS: base64 `ApplicationToken` strings (from FamilyActivityPicker).
  Future<List<AppIdentifier>> restrictApps(List<AppIdentifier> identifiers) {
    return _platform.setRestrictedApps(identifiers).throwTypedPauzaError();
  }

  /// Restricts a single app.
  ///
  /// Returns `true` if the restricted set changed, `false` if it was a no-op.
  Future<bool> restrictApp(AppIdentifier identifier) {
    return _platform.addRestrictedApp(identifier).throwTypedPauzaError();
  }

  /// Removes restriction from a specific app.
  ///
  /// [identifier] - Opaque identifier of the app to unblock.
  ///
  /// Returns `true` if the restricted set changed, `false` if it was a no-op.
  Future<bool> unrestrictApp(AppIdentifier identifier) {
    return _platform.removeRestriction(identifier).throwTypedPauzaError();
  }

  /// Removes all app restrictions.
  Future<void> clearAllRestrictions() {
    return _platform.removeAllRestrictions().throwTypedPauzaError();
  }

  /// Returns the list of currently restricted app identifiers.
  Future<List<AppIdentifier>> getRestrictedApps() {
    return _platform.getRestrictedApps().throwTypedPauzaError();
  }

  /// Checks if a specific app is currently restricted.
  Future<bool> isAppRestricted(AppIdentifier identifier) {
    return _platform.isRestricted(identifier).throwTypedPauzaError();
  }

  /// Returns whether the restriction session is active right now.
  Future<bool> isRestrictionSessionActiveNow() {
    return _platform.isRestrictionSessionActiveNow().throwTypedPauzaError();
  }

  /// Returns whether a restriction session is configured.
  Future<bool> isRestrictionSessionConfigured() {
    return _platform.isRestrictionSessionConfigured().throwTypedPauzaError();
  }

  /// Pauses restriction enforcement for the given [duration].
  Future<void> pauseEnforcement(Duration duration) {
    return _platform.pauseEnforcement(duration).throwTypedPauzaError();
  }

  /// Resumes restriction enforcement immediately.
  Future<void> resumeEnforcement() {
    return _platform.resumeEnforcement().throwTypedPauzaError();
  }

  /// Starts a manual restriction session.
  Future<void> startRestrictionSession() {
    return _platform.startRestrictionSession().throwTypedPauzaError();
  }

  /// Ends a manual restriction session.
  Future<void> endRestrictionSession() {
    return _platform.endRestrictionSession().throwTypedPauzaError();
  }

  /// Returns the current restriction session snapshot.
  Future<RestrictionSession> getRestrictionSession() {
    return _platform.getRestrictionSession().throwTypedPauzaError();
  }

  /// Upserts one mode with a single schedule and blocked identifiers.
  Future<void> upsertScheduledMode(RestrictionScheduledMode mode) {
    return _platform.upsertScheduledMode(mode).throwTypedPauzaError();
  }

  /// Removes one scheduled mode by [modeId].
  Future<void> removeScheduledMode(String modeId) {
    return _platform.removeScheduledMode(modeId).throwTypedPauzaError();
  }

  /// Enables or disables scheduled mode enforcement globally.
  Future<void> setScheduledModesEnabled(bool enabled) {
    return _platform.setScheduledModesEnabled(enabled).throwTypedPauzaError();
  }

  /// Loads scheduled modes configuration.
  Future<RestrictionScheduledModesConfig> getScheduledModesConfig() {
    return _platform.getScheduledModesConfig().throwTypedPauzaError();
  }
}
