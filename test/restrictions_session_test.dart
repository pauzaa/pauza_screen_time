import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/app_restriction_platform.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/data/app_restriction_manager.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/channel_name.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/method_names.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/restrictions_method_channel.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_modes_config.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode_source.dart';
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
                'activeModeId': 'focus',
                'activeModeSource': 'schedule',
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
      expect(session.activeModeId, 'focus');
      expect(session.activeModeSource, RestrictionModeSource.schedule);
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
      expect(session.isManuallyEnabled, isFalse);
      expect(session.isScheduleEnabled, isFalse);
      expect(session.isInScheduleNow, isFalse);
      expect(session.pausedUntil, isNull);
      expect(session.restrictedApps, isEmpty);
      expect(session.activeModeId, isNull);
      expect(session.activeModeSource, RestrictionModeSource.none);
    });

    test(
      'getRestrictionSession throws on malformed activeModeSource',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method ==
                  RestrictionsMethodNames.getRestrictionSession) {
                return {'activeModeSource': 'invalid'};
              }
              return null;
            });

        await expectLater(
          methodChannel.getRestrictionSession(),
          throwsA(
            isA<PlatformException>().having(
              (error) => error.code,
              'code',
              'INTERNAL_FAILURE',
            ),
          ),
        );
      },
    );

    test('getModesConfig throws on malformed payload', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == RestrictionsMethodNames.getModesConfig) {
              return {
                'enabled': true,
                'modes': [
                  {'modeId': 123},
                ],
              };
            }
            return null;
          });

      await expectLater(
        methodChannel.getModesConfig(),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'INTERNAL_FAILURE',
          ),
        ),
      );
    });

    test('start/end mode session invoke platform methods', () async {
      var startCalled = false;
      var endCalled = false;
      Object? capturedModeId;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == RestrictionsMethodNames.startModeSession) {
              startCalled = true;
              capturedModeId = (call.arguments as Map)['modeId'];
            } else if (call.method == RestrictionsMethodNames.endModeSession) {
              endCalled = true;
            }
            return null;
          });

      await methodChannel.startModeSession('focus');
      await methodChannel.endModeSession();
      expect(startCalled, isTrue);
      expect(endCalled, isTrue);
      expect(capturedModeId, 'focus');
    });
  });

  group('AppRestrictionManager delegation', () {
    test('delegates mode APIs to platform', () async {
      final fakePlatform = _FakeAppRestrictionPlatform();
      final manager = AppRestrictionManager(platform: fakePlatform);

      await manager.upsertMode(
        const RestrictionMode(
          modeId: 'focus',
          isEnabled: true,
          blockedAppIds: [AppIdentifier('com.example.app')],
        ),
      );
      await manager.removeMode('focus');
      await manager.setModesEnabled(true);
      final modesConfig = await manager.getModesConfig();
      await manager.pauseEnforcement(const Duration(seconds: 30));
      await manager.resumeEnforcement();
      await manager.startModeSession('focus');
      await manager.endModeSession();
      final session = await manager.getRestrictionSession();

      expect(fakePlatform.upsertModeCalled, isTrue);
      expect(fakePlatform.removeModeCalled, isTrue);
      expect(fakePlatform.setModesEnabledCalled, isTrue);
      expect(fakePlatform.getModesConfigCalled, isTrue);
      expect(fakePlatform.pauseEnforcementCalled, isTrue);
      expect(fakePlatform.resumeEnforcementCalled, isTrue);
      expect(fakePlatform.startModeSessionCalled, isTrue);
      expect(fakePlatform.endModeSessionCalled, isTrue);
      expect(fakePlatform.getRestrictionSessionCalled, isTrue);
      expect(modesConfig.enabled, isTrue);
      expect(session.activeModeId, 'focus');
      expect(session.activeModeSource, RestrictionModeSource.manual);
    });
  });

  group('AppRestrictionManager decode failures', () {
    const channel = MethodChannel(restrictionsChannelName);

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'getRestrictionSession surfaces malformed payload as typed PauzaError',
      () async {
        final manager = AppRestrictionManager(
          platform: RestrictionsMethodChannel(channel: channel),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method ==
                  RestrictionsMethodNames.getRestrictionSession) {
                return {'activeModeSource': 'bad'};
              }
              return null;
            });

        await expectLater(
          manager.getRestrictionSession(),
          throwsA(isA<PauzaInternalFailureError>()),
        );
      },
    );

    test(
      'getModesConfig surfaces malformed payload as typed PauzaError',
      () async {
        final manager = AppRestrictionManager(
          platform: RestrictionsMethodChannel(channel: channel),
        );
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == RestrictionsMethodNames.getModesConfig) {
                return {
                  'enabled': true,
                  'modes': [
                    {'modeId': 1},
                  ],
                };
              }
              return null;
            });

        await expectLater(
          manager.getModesConfig(),
          throwsA(isA<PauzaInternalFailureError>()),
        );
      },
    );
  });
}

class _FakeAppRestrictionPlatform extends AppRestrictionPlatform {
  bool upsertModeCalled = false;
  bool removeModeCalled = false;
  bool setModesEnabledCalled = false;
  bool getModesConfigCalled = false;
  bool pauseEnforcementCalled = false;
  bool resumeEnforcementCalled = false;
  bool startModeSessionCalled = false;
  bool endModeSessionCalled = false;
  bool getRestrictionSessionCalled = false;

  @override
  Future<void> configureShield(Map<String, dynamic> configuration) async {}

  @override
  Future<RestrictionModesConfig> getModesConfig() async {
    getModesConfigCalled = true;
    return const RestrictionModesConfig(enabled: true, modes: []);
  }

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
      activeModeId: 'focus',
      activeModeSource: RestrictionModeSource.manual,
    );
  }

  @override
  Future<bool> isRestrictionSessionActiveNow() async => true;

  @override
  Future<bool> isRestrictionSessionConfigured() async => true;

  @override
  Future<void> pauseEnforcement(Duration duration) async {
    pauseEnforcementCalled = true;
  }

  @override
  Future<void> removeMode(String modeId) async {
    removeModeCalled = true;
  }

  @override
  Future<void> resumeEnforcement() async {
    resumeEnforcementCalled = true;
  }

  @override
  Future<void> endModeSession() async {
    endModeSessionCalled = true;
  }

  @override
  Future<void> setModesEnabled(bool enabled) async {
    setModesEnabledCalled = true;
  }

  @override
  Future<void> startModeSession(String modeId) async {
    startModeSessionCalled = true;
  }

  @override
  Future<void> upsertMode(RestrictionMode mode) async {
    upsertModeCalled = true;
  }
}
