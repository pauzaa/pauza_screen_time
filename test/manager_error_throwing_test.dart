import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/app_restriction_platform.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/data/app_restriction_manager.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_modes_config.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode_source.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_session.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/shield_configuration.dart';

void main() {
  test('manager throws typed PauzaError for platform exception', () async {
    final manager = AppRestrictionManager(
      platform: _FailingRestrictionPlatform(),
    );

    await expectLater(
      manager.upsertMode(
        const RestrictionMode(
          modeId: 'focus',
          isEnabled: true,
          blockedAppIds: [AppIdentifier('x')],
        ),
      ),
      throwsA(isA<PauzaMissingPermissionError>()),
    );
  });
}

class _FailingRestrictionPlatform extends AppRestrictionPlatform {
  @override
  Future<void> configureShield(ShieldConfiguration configuration) async {}

  @override
  Future<RestrictionModesConfig> getModesConfig() async =>
      const RestrictionModesConfig(enabled: false, modes: []);

  @override
  Future<RestrictionSession> getRestrictionSession() async =>
      const RestrictionSession(
        isActiveNow: false,
        isPausedNow: false,
        isScheduleEnabled: false,
        isInScheduleNow: false,
        pausedUntil: null,
        restrictedApps: [],
        activeModeId: null,
        activeModeSource: RestrictionModeSource.none,
      );

  @override
  Future<bool> isRestrictionSessionActiveNow() async => false;

  @override
  Future<bool> isRestrictionSessionConfigured() async => false;

  @override
  Future<void> pauseEnforcement(Duration duration) async {}

  @override
  Future<void> removeMode(String modeId) async {}

  @override
  Future<void> resumeEnforcement() async {}

  @override
  Future<void> endModeSession() async {}

  @override
  Future<void> setModesEnabled(bool enabled) async {}

  @override
  Future<void> startModeSession(String modeId) async {}

  @override
  Future<void> upsertMode(RestrictionMode mode) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'missing');
  }
}
