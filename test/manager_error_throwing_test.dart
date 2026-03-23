import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/app_restriction_platform.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/data/app_restriction_manager.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_lifecycle_event.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_modes_config.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode_source.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_state.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/shield_configuration.dart';

void main() {
  test('manager throws typed PauzaError for upsertMode platform exception', () async {
    final manager = AppRestrictionManager(platform: _FailingRestrictionPlatform());

    await expectLater(
      manager.upsertMode(const RestrictionMode(modeId: 'focus', blockedAppIds: [AppIdentifier('x')])),
      throwsA(isA<PauzaMissingPermissionError>()),
    );
  });

  test('manager throws typed PauzaError for setModesEnabled', () async {
    final manager = AppRestrictionManager(platform: _FailingRestrictionPlatform());

    await expectLater(manager.setModesEnabled(true), throwsA(isA<PauzaMissingPermissionError>()));
  });

  test('manager throws typed PauzaError for startSession', () async {
    final manager = AppRestrictionManager(platform: _FailingRestrictionPlatform());

    await expectLater(
      manager.startSession(const RestrictionMode(modeId: 'focus', blockedAppIds: [AppIdentifier('x')])),
      throwsA(isA<PauzaMissingPermissionError>()),
    );
  });

  test('manager throws typed PauzaError for pauseEnforcement', () async {
    final manager = AppRestrictionManager(platform: _FailingRestrictionPlatform());

    await expectLater(
      manager.pauseEnforcement(const Duration(minutes: 1)),
      throwsA(isA<PauzaMissingPermissionError>()),
    );
  });

  test('manager throws typed PauzaError for resumeEnforcement', () async {
    final manager = AppRestrictionManager(platform: _FailingRestrictionPlatform());

    await expectLater(manager.resumeEnforcement(), throwsA(isA<PauzaMissingPermissionError>()));
  });

  test('manager throws typed PauzaError for getPendingLifecycleEvents', () async {
    final manager = AppRestrictionManager(platform: _FailingRestrictionPlatform());

    await expectLater(manager.getPendingLifecycleEvents(), throwsA(isA<PauzaMissingPermissionError>()));
  });

  test('manager throws typed PauzaError for ackLifecycleEvents', () async {
    final manager = AppRestrictionManager(platform: _FailingRestrictionPlatform());

    await expectLater(
      manager.ackLifecycleEvents(throughEventId: 'event-1'),
      throwsA(isA<PauzaMissingPermissionError>()),
    );
  });
}

class _FailingRestrictionPlatform extends AppRestrictionPlatform {
  @override
  Future<void> configureShield(ShieldConfiguration configuration) async {}

  @override
  Future<RestrictionModesConfig> getModesConfig() async => const RestrictionModesConfig(enabled: false, modes: []);

  @override
  Future<RestrictionState> getRestrictionSession() async => const RestrictionState(
    isScheduleEnabled: false,
    isInScheduleNow: false,
    pausedUntil: null,
    activeMode: null,
    activeModeSource: RestrictionModeSource.none,
    currentSessionEvents: <RestrictionLifecycleEvent>[],
  );

  @override
  Future<bool> isRestrictionSessionActiveNow() async => false;

  @override
  Future<void> removeMode(String modeId) async {}

  @override
  Future<void> endSession({Duration? duration, RestrictionLifecycleReason? reason}) async {}

  @override
  Future<List<RestrictionLifecycleEvent>> getPendingLifecycleEvents({int limit = 200}) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'missing');
  }

  @override
  Future<void> setModesEnabled(bool enabled) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'missing');
  }

  @override
  Future<void> startSession(RestrictionMode mode, {Duration? duration}) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'missing');
  }

  @override
  Future<void> upsertMode(RestrictionMode mode) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'missing');
  }

  @override
  Future<void> pauseEnforcement(Duration duration) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'missing');
  }

  @override
  Future<void> resumeEnforcement() async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'missing');
  }

  @override
  Future<void> ackLifecycleEvents({required String throughEventId}) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'missing');
  }
}
