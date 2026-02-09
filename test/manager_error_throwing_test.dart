import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/app_restriction_platform.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/data/app_restriction_manager.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_session.dart';

void main() {
  test('manager throws typed PauzaError for platform exception', () async {
    final manager = AppRestrictionManager(
      platform: _FailingRestrictionPlatform(),
    );

    await expectLater(
      manager.restrictApps(const [AppIdentifier('x')]),
      throwsA(isA<PauzaMissingPermissionError>()),
    );
  });
}

class _FailingRestrictionPlatform extends AppRestrictionPlatform {
  @override
  Future<bool> addRestrictedApp(AppIdentifier identifier) async => false;

  @override
  Future<void> configureShield(Map<String, dynamic> configuration) async {}

  @override
  Future<List<AppIdentifier>> getRestrictedApps() async => const [];

  @override
  Future<RestrictionSession> getRestrictionSession() async =>
      const RestrictionSession(
        isActiveNow: false,
        isPausedNow: false,
        isManuallyEnabled: true,
        isScheduleEnabled: false,
        isInScheduleNow: false,
        pausedUntil: null,
        restrictedApps: [],
      );

  @override
  Future<bool> isRestricted(AppIdentifier identifier) async => false;

  @override
  Future<bool> isRestrictionSessionActiveNow() async => false;

  @override
  Future<bool> isRestrictionSessionConfigured() async => false;

  @override
  Future<void> pauseEnforcement(Duration duration) async {}

  @override
  Future<void> removeAllRestrictions() async {}

  @override
  Future<bool> removeRestriction(AppIdentifier identifier) async => false;

  @override
  Future<void> resumeEnforcement() async {}

  @override
  Future<void> startRestrictionSession() async {}

  @override
  Future<void> endRestrictionSession() async {}

  @override
  Future<List<AppIdentifier>> setRestrictedApps(
    List<AppIdentifier> identifiers,
  ) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'missing');
  }
}
