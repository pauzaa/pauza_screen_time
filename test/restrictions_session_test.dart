import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/app_restriction_platform.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/data/app_restriction_manager.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/channel_name.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/method_names.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/restrictions_method_channel.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RestrictionsMethodChannel session APIs', () {
    const channel = MethodChannel(restrictionsChannelName);
    final methodChannel = RestrictionsMethodChannel(channel: channel);

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'isRestrictionSessionActiveNow returns false on null result',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method ==
                  RestrictionsMethodNames.isRestrictionSessionActiveNow) {
                return null;
              }
              return null;
            });

        final isActive = await methodChannel.isRestrictionSessionActiveNow();
        expect(isActive, isFalse);
      },
    );

    test('getRestrictionSession parses valid payload', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == RestrictionsMethodNames.getRestrictionSession) {
              return {
                'isActiveNow': true,
                'isPausedNow': true,
                'isManuallyEnabled': false,
                'isScheduleEnabled': true,
                'isInScheduleNow': true,
                'pausedUntilEpochMs': 1,
                'restrictedApps': ['x'],
              };
            }
            return null;
          });

      final session = await methodChannel.getRestrictionSession();
      expect(session.isActiveNow, isTrue);
      expect(session.isPausedNow, isTrue);
      expect(session.isManuallyEnabled, isFalse);
      expect(session.isScheduleEnabled, isTrue);
      expect(session.isInScheduleNow, isTrue);
      expect(session.pausedUntil, DateTime.fromMillisecondsSinceEpoch(1));
      expect(session.restrictedApps, const [AppIdentifier('x')]);
    });

    test('getRestrictionSession defaults missing keys', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == RestrictionsMethodNames.getRestrictionSession) {
              return <String, dynamic>{};
            }
            return null;
          });

      final session = await methodChannel.getRestrictionSession();
      expect(session, isA<RestrictionSession>());
      expect(session.isActiveNow, isFalse);
      expect(session.isPausedNow, isFalse);
      expect(session.isManuallyEnabled, isTrue);
      expect(session.isScheduleEnabled, isFalse);
      expect(session.isInScheduleNow, isFalse);
      expect(session.pausedUntil, isNull);
      expect(session.restrictedApps, isEmpty);
    });

    test(
      'isRestrictionSessionConfigured returns false on null result',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method ==
                  RestrictionsMethodNames.isRestrictionSessionConfigured) {
                return null;
              }
              return null;
            });

        final isConfigured = await methodChannel
            .isRestrictionSessionConfigured();
        expect(isConfigured, isFalse);
      },
    );

    test('pauseEnforcement sends durationMs argument', () async {
      Object? capturedDurationMs;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == RestrictionsMethodNames.pauseEnforcement) {
              capturedDurationMs = (call.arguments as Map)['durationMs'];
            }
            return null;
          });

      await methodChannel.pauseEnforcement(const Duration(minutes: 2));
      expect(capturedDurationMs, 120000);
    });

    test('resumeEnforcement invokes platform method', () async {
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == RestrictionsMethodNames.resumeEnforcement) {
              called = true;
            }
            return null;
          });

      await methodChannel.resumeEnforcement();
      expect(called, isTrue);
    });

    test('start/end restriction session invoke platform methods', () async {
      var startCalled = false;
      var endCalled = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method ==
                RestrictionsMethodNames.startRestrictionSession) {
              startCalled = true;
            } else if (call.method ==
                RestrictionsMethodNames.endRestrictionSession) {
              endCalled = true;
            }
            return null;
          });

      await methodChannel.startRestrictionSession();
      await methodChannel.endRestrictionSession();
      expect(startCalled, isTrue);
      expect(endCalled, isTrue);
    });
  });

  group('AppRestrictionManager session delegation', () {
    test('delegates session methods to platform', () async {
      final fakePlatform = _FakeAppRestrictionPlatform();
      final manager = AppRestrictionManager(platform: fakePlatform);

      final isActiveNow = await manager.isRestrictionSessionActiveNow();
      final isConfigured = await manager.isRestrictionSessionConfigured();
      await manager.pauseEnforcement(const Duration(seconds: 30));
      await manager.resumeEnforcement();
      await manager.startRestrictionSession();
      await manager.endRestrictionSession();
      final session = await manager.getRestrictionSession();

      expect(fakePlatform.isRestrictionSessionActiveNowCalled, isTrue);
      expect(fakePlatform.isRestrictionSessionConfiguredCalled, isTrue);
      expect(fakePlatform.pauseEnforcementCalled, isTrue);
      expect(fakePlatform.resumeEnforcementCalled, isTrue);
      expect(fakePlatform.startRestrictionSessionCalled, isTrue);
      expect(fakePlatform.endRestrictionSessionCalled, isTrue);
      expect(fakePlatform.getRestrictionSessionCalled, isTrue);
      expect(isActiveNow, isTrue);
      expect(isConfigured, isTrue);
      expect(session.isActiveNow, isTrue);
      expect(session.isPausedNow, isFalse);
      expect(session.isManuallyEnabled, isTrue);
      expect(session.isScheduleEnabled, isFalse);
      expect(session.isInScheduleNow, isFalse);
      expect(session.pausedUntil, isNull);
      expect(session.restrictedApps, const [
        AppIdentifier.android('com.example.app'),
      ]);
    });
  });
}

class _FakeAppRestrictionPlatform extends AppRestrictionPlatform {
  bool isRestrictionSessionActiveNowCalled = false;
  bool isRestrictionSessionConfiguredCalled = false;
  bool pauseEnforcementCalled = false;
  bool resumeEnforcementCalled = false;
  bool startRestrictionSessionCalled = false;
  bool endRestrictionSessionCalled = false;
  bool getRestrictionSessionCalled = false;

  @override
  Future<bool> addRestrictedApp(AppIdentifier identifier) async => false;

  @override
  Future<void> configureShield(Map<String, dynamic> configuration) async {}

  @override
  Future<List<AppIdentifier>> getRestrictedApps() async => const [];

  @override
  Future<bool> isRestricted(AppIdentifier identifier) async => false;

  @override
  Future<void> removeAllRestrictions() async {}

  @override
  Future<bool> removeRestriction(AppIdentifier identifier) async => false;

  @override
  Future<List<AppIdentifier>> setRestrictedApps(
    List<AppIdentifier> identifiers,
  ) async => const [];

  @override
  Future<RestrictionSession> getRestrictionSession() async {
    getRestrictionSessionCalled = true;
    return const RestrictionSession(
      isActiveNow: true,
      isPausedNow: false,
      isManuallyEnabled: true,
      isScheduleEnabled: false,
      isInScheduleNow: false,
      pausedUntil: null,
      restrictedApps: [AppIdentifier('com.example.app')],
    );
  }

  @override
  Future<bool> isRestrictionSessionActiveNow() async {
    isRestrictionSessionActiveNowCalled = true;
    return true;
  }

  @override
  Future<bool> isRestrictionSessionConfigured() async {
    isRestrictionSessionConfiguredCalled = true;
    return true;
  }

  @override
  Future<void> pauseEnforcement(Duration duration) async {
    pauseEnforcementCalled = true;
  }

  @override
  Future<void> resumeEnforcement() async {
    resumeEnforcementCalled = true;
  }

  @override
  Future<void> startRestrictionSession() async {
    startRestrictionSessionCalled = true;
  }

  @override
  Future<void> endRestrictionSession() async {
    endRestrictionSessionCalled = true;
  }
}
