import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/app_restriction_platform.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/data/app_restriction_manager.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/channel_name.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/method_names.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/restrictions_method_channel.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_lifecycle_event.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_modes_config.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode_source.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_state.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/shield_configuration.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RestrictionsMethodChannel session APIs', () {
    const channel = MethodChannel(restrictionsChannelName);
    final methodChannel = RestrictionsMethodChannel(channel: channel);

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('getRestrictionSession parses valid payload', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.getRestrictionSession) {
          return {
            'isScheduleEnabled': true,
            'isInScheduleNow': true,
            'pausedUntilEpochMs': 1,
            'activeMode': {
              'modeId': 'focus',
              'blockedAppIds': ['x'],
            },
            'activeModeSource': 'schedule',
            'currentSessionEvents': [
              {
                'id': '0000000000001-0000000001',
                'sessionId': 'session-1',
                'modeId': 'focus',
                'action': 'START',
                'source': 'schedule',
                'reason': 'schedule_start',
                'occurredAtEpochMs': 1,
              },
            ],
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
      expect(session.activeMode, isNotNull);
      expect(session.activeMode!.modeId, 'focus');
      expect(session.activeMode!.blockedAppIds, const [AppIdentifier('x')]);
      expect(session.activeModeSource, RestrictionModeSource.schedule);
      expect(session.currentSessionEvents, hasLength(1));
      expect(session.currentSessionEvents.first.sessionId, 'session-1');
    });

    test('getRestrictionSession preserves full current session event log', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.getRestrictionSession) {
          return {
            'activeMode': {
              'modeId': 'focus',
              'blockedAppIds': ['x'],
            },
            'activeModeSource': 'manual',
            'currentSessionEvents': [
              {
                'id': '0000000000001-0000000001',
                'sessionId': 'session-1',
                'modeId': 'focus',
                'action': 'START',
                'source': 'manual',
                'reason': 'start',
                'occurredAtEpochMs': 1,
              },
              {
                'id': '0000000000002-0000000002',
                'sessionId': 'session-1',
                'modeId': 'focus',
                'action': 'PAUSE',
                'source': 'manual',
                'reason': 'pause',
                'occurredAtEpochMs': 2,
              },
            ],
          };
        }
        return null;
      });

      final session = await methodChannel.getRestrictionSession();
      expect(session.currentSessionEvents, hasLength(2));
      expect(session.currentSessionEvents.first.action, RestrictionLifecycleAction.start);
      expect(session.currentSessionEvents.last.action, RestrictionLifecycleAction.pause);
      expect(session.currentSessionEvents.last.occurredAt, DateTime.fromMillisecondsSinceEpoch(2, isUtc: true));
    });

    test('getRestrictionSession defaults missing keys', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.getRestrictionSession) {
          return <String, dynamic>{
            'currentSessionEvents': <String, dynamic>{'bad': true},
          };
        }
        return null;
      });

      final session = await methodChannel.getRestrictionSession();
      expect(session, isA<RestrictionState>());
      expect(session.isActiveNow, isFalse);
      expect(session.isPausedNow, isFalse);
      expect(session.isManuallyEnabled, isFalse);
      expect(session.isScheduleEnabled, isFalse);
      expect(session.isInScheduleNow, isFalse);
      expect(session.pausedUntil, isNull);
      expect(session.activeMode, isNull);
      expect(session.activeModeSource, RestrictionModeSource.none);
      expect(session.currentSessionEvents, isEmpty);
    });

    test('getRestrictionSession throws on malformed activeModeSource', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.getRestrictionSession) {
          return {'activeModeSource': 'invalid'};
        }
        return null;
      });

      await expectLater(
        methodChannel.getRestrictionSession(),
        throwsA(isA<PlatformException>().having((error) => error.code, 'code', 'INTERNAL_FAILURE')),
      );
    });

    test('getModesConfig throws on malformed payload', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
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
        throwsA(isA<PlatformException>().having((error) => error.code, 'code', 'INTERNAL_FAILURE')),
      );
    });

    test('start/end session invoke platform methods', () async {
      var startCalled = false;
      var endCalled = false;
      Object? capturedModeId;
      Object? capturedBlockedAppIds;
      Object? capturedDurationMs;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.startSession) {
          startCalled = true;
          capturedModeId = (call.arguments as Map)['modeId'];
          capturedBlockedAppIds = (call.arguments as Map)['blockedAppIds'];
          capturedDurationMs = (call.arguments as Map)['durationMs'];
        } else if (call.method == RestrictionsMethodNames.endSession) {
          endCalled = true;
        }
        return null;
      });

      await methodChannel.startSession(
        const RestrictionMode(modeId: 'focus', blockedAppIds: [AppIdentifier('com.example.focus')]),
      );
      await methodChannel.endSession();
      expect(startCalled, isTrue);
      expect(endCalled, isTrue);
      expect(capturedModeId, 'focus');
      expect(capturedBlockedAppIds, ['com.example.focus']);
      expect(capturedDurationMs, isNull);
    });

    test('endSession surfaces INVALID_ARGUMENT when no active session exists', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.endSession) {
          throw PlatformException(code: 'INVALID_ARGUMENT', message: 'No active restriction session to end');
        }
        return null;
      });

      await expectLater(
        methodChannel.endSession(),
        throwsA(
          isA<PlatformException>()
              .having((error) => error.code, 'code', 'INVALID_ARGUMENT')
              .having((error) => error.message, 'message', 'No active restriction session to end'),
        ),
      );
    });

    test('startSession passes optional durationMs', () async {
      Object? capturedDurationMs;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.startSession) {
          capturedDurationMs = (call.arguments as Map)['durationMs'];
        }
        return null;
      });

      await methodChannel.startSession(
        const RestrictionMode(modeId: 'focus', blockedAppIds: [AppIdentifier('com.example.focus')]),
        duration: const Duration(minutes: 15),
      );

      expect(capturedDurationMs, const Duration(minutes: 15).inMilliseconds);
    });

    test('lifecycle event APIs invoke platform methods', () async {
      Object? capturedLimit;
      Object? capturedAckId;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.getPendingLifecycleEvents) {
          capturedLimit = (call.arguments as Map)['limit'];
          return [
            {
              'id': '0000000000001-0000000001',
              'sessionId': 'session-1',
              'modeId': 'focus',
              'action': 'START',
              'source': 'manual',
              'reason': 'test',
              'occurredAtEpochMs': 1,
            },
          ];
        }
        if (call.method == RestrictionsMethodNames.ackLifecycleEvents) {
          capturedAckId = (call.arguments as Map)['throughEventId'];
          return null;
        }
        return null;
      });

      final events = await methodChannel.getPendingLifecycleEvents(limit: 50);
      await methodChannel.ackLifecycleEvents(throughEventId: '0000000000001-0000000001');

      expect(capturedLimit, 50);
      expect(events, hasLength(1));
      expect(events.first.action, RestrictionLifecycleAction.start);
      expect(capturedAckId, '0000000000001-0000000001');
    });

    test('getPendingLifecycleEvents throws on malformed payload', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.getPendingLifecycleEvents) {
          return [
            {'id': 'event-1', 'sessionId': ''},
          ];
        }
        return null;
      });

      await expectLater(
        methodChannel.getPendingLifecycleEvents(),
        throwsA(isA<PlatformException>().having((error) => error.code, 'code', 'INTERNAL_FAILURE')),
      );
    });
  });

  group('AppRestrictionManager delegation', () {
    test('delegates mode APIs to platform', () async {
      final fakePlatform = _FakeAppRestrictionPlatform();
      final manager = AppRestrictionManager(platform: fakePlatform);

      await manager.upsertMode(
        const RestrictionMode(modeId: 'focus', blockedAppIds: [AppIdentifier('com.example.app')]),
      );
      await manager.removeMode('focus');
      await manager.setModesEnabled(true);
      final modesConfig = await manager.getModesConfig();
      await manager.pauseEnforcement(const Duration(seconds: 30));
      await manager.resumeEnforcement();
      await manager.startSession(
        const RestrictionMode(modeId: 'focus', blockedAppIds: [AppIdentifier('com.example.app')]),
        duration: const Duration(minutes: 10),
      );
      await manager.endSession();
      final lifecycleEvents = await manager.getPendingLifecycleEvents();
      await manager.ackLifecycleEvents(throughEventId: 'event-1');
      final session = await manager.getRestrictionSession();

      expect(fakePlatform.upsertModeCalled, isTrue);
      expect(fakePlatform.removeModeCalled, isTrue);
      expect(fakePlatform.setModesEnabledCalled, isTrue);
      expect(fakePlatform.getModesConfigCalled, isTrue);
      expect(fakePlatform.pauseEnforcementCalled, isTrue);
      expect(fakePlatform.resumeEnforcementCalled, isTrue);
      expect(fakePlatform.startSessionCalled, isTrue);
      expect(fakePlatform.startSessionDuration, const Duration(minutes: 10));
      expect(fakePlatform.endSessionCalled, isTrue);
      expect(fakePlatform.getPendingLifecycleEventsCalled, isTrue);
      expect(fakePlatform.ackLifecycleEventsCalled, isTrue);
      expect(fakePlatform.getRestrictionSessionCalled, isTrue);
      expect(modesConfig.enabled, isTrue);
      expect(lifecycleEvents, hasLength(1));
      expect(session.activeMode?.modeId, 'focus');
      expect(session.activeModeSource, RestrictionModeSource.manual);
    });

    test('startSession delegates mode payload without upsert dependency', () async {
      final fakePlatform = _FakeAppRestrictionPlatform();
      final manager = AppRestrictionManager(platform: fakePlatform);
      const mode = RestrictionMode(modeId: 'manual-focus', blockedAppIds: [AppIdentifier('com.example.social')]);

      await manager.startSession(mode);

      expect(fakePlatform.upsertModeCalled, isFalse);
      expect(fakePlatform.startSessionCalled, isTrue);
      expect(fakePlatform.calls, equals(['startSession:manual-focus']));
    });
  });

  group('AppRestrictionManager decode failures', () {
    const channel = MethodChannel(restrictionsChannelName);

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    });

    test('getRestrictionSession surfaces malformed payload as typed PauzaError', () async {
      final manager = AppRestrictionManager(platform: RestrictionsMethodChannel(channel: channel));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.getRestrictionSession) {
          return {'activeModeSource': 'bad'};
        }
        return null;
      });

      await expectLater(manager.getRestrictionSession(), throwsA(isA<PauzaInternalFailureError>()));
    });

    test('getModesConfig surfaces malformed payload as typed PauzaError', () async {
      final manager = AppRestrictionManager(platform: RestrictionsMethodChannel(channel: channel));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
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

      await expectLater(manager.getModesConfig(), throwsA(isA<PauzaInternalFailureError>()));
    });

    test('endSession surfaces INVALID_ARGUMENT as typed PauzaError', () async {
      final manager = AppRestrictionManager(platform: RestrictionsMethodChannel(channel: channel));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.endSession) {
          throw PlatformException(code: 'INVALID_ARGUMENT', message: 'No active restriction session to end');
        }
        return null;
      });

      await expectLater(
        manager.endSession(),
        throwsA(
          isA<PauzaInvalidArgumentError>().having(
            (error) => error.message,
            'message',
            'No active restriction session to end',
          ),
        ),
      );
    });

    test('pauseEnforcement surfaces no active session as typed PauzaError', () async {
      final manager = AppRestrictionManager(platform: RestrictionsMethodChannel(channel: channel));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.pauseEnforcement) {
          throw PlatformException(code: 'INVALID_ARGUMENT', message: 'No active restriction session to pause.');
        }
        return null;
      });

      await expectLater(
        manager.pauseEnforcement(const Duration(minutes: 1)),
        throwsA(
          isA<PauzaInvalidArgumentError>().having(
            (error) => error.message,
            'message',
            'No active restriction session to pause.',
          ),
        ),
      );
    });

    test('pauseEnforcement surfaces already paused as typed PauzaError', () async {
      final manager = AppRestrictionManager(platform: RestrictionsMethodChannel(channel: channel));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.pauseEnforcement) {
          throw PlatformException(code: 'INVALID_ARGUMENT', message: 'Restriction enforcement is already paused.');
        }
        return null;
      });

      await expectLater(
        manager.pauseEnforcement(const Duration(minutes: 1)),
        throwsA(
          isA<PauzaInvalidArgumentError>().having(
            (error) => error.message,
            'message',
            'Restriction enforcement is already paused.',
          ),
        ),
      );
    });

    test('resumeEnforcement surfaces no active session as typed PauzaError', () async {
      final manager = AppRestrictionManager(platform: RestrictionsMethodChannel(channel: channel));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.resumeEnforcement) {
          throw PlatformException(code: 'INVALID_ARGUMENT', message: 'No active restriction session to resume.');
        }
        return null;
      });

      await expectLater(
        manager.resumeEnforcement(),
        throwsA(
          isA<PauzaInvalidArgumentError>().having(
            (error) => error.message,
            'message',
            'No active restriction session to resume.',
          ),
        ),
      );
    });

    test('resumeEnforcement surfaces not paused as typed PauzaError', () async {
      final manager = AppRestrictionManager(platform: RestrictionsMethodChannel(channel: channel));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == RestrictionsMethodNames.resumeEnforcement) {
          throw PlatformException(code: 'INVALID_ARGUMENT', message: 'Restriction enforcement is not paused.');
        }
        return null;
      });

      await expectLater(
        manager.resumeEnforcement(),
        throwsA(
          isA<PauzaInvalidArgumentError>().having(
            (error) => error.message,
            'message',
            'Restriction enforcement is not paused.',
          ),
        ),
      );
    });
  });
}

class _FakeAppRestrictionPlatform extends AppRestrictionPlatform {
  final List<String> calls = <String>[];
  bool upsertModeCalled = false;
  bool removeModeCalled = false;
  bool setModesEnabledCalled = false;
  bool getModesConfigCalled = false;
  bool pauseEnforcementCalled = false;
  bool resumeEnforcementCalled = false;
  bool startSessionCalled = false;
  Duration? startSessionDuration;
  bool endSessionCalled = false;
  bool getPendingLifecycleEventsCalled = false;
  bool ackLifecycleEventsCalled = false;
  bool getRestrictionSessionCalled = false;

  @override
  Future<void> configureShield(ShieldConfiguration configuration) async {}

  @override
  Future<RestrictionModesConfig> getModesConfig() async {
    getModesConfigCalled = true;
    return const RestrictionModesConfig(enabled: true, modes: []);
  }

  @override
  Future<List<RestrictionLifecycleEvent>> getPendingLifecycleEvents({int limit = 200}) async {
    getPendingLifecycleEventsCalled = true;
    return <RestrictionLifecycleEvent>[
      RestrictionLifecycleEvent(
        id: 'event-1',
        sessionId: 'session-1',
        modeId: 'focus',
        action: RestrictionLifecycleAction.start,
        source: RestrictionLifecycleSource.manual,
        reason: 'test',
        occurredAt: DateTime.utc(1970, 1, 1, 0, 0, 0, 1),
      ),
    ];
  }

  @override
  Future<RestrictionState> getRestrictionSession() async {
    getRestrictionSessionCalled = true;
    return const RestrictionState(
      isScheduleEnabled: false,
      isInScheduleNow: false,
      pausedUntil: null,
      activeMode: RestrictionMode(modeId: 'focus', blockedAppIds: [AppIdentifier('com.example.app')]),
      activeModeSource: RestrictionModeSource.manual,
      currentSessionEvents: <RestrictionLifecycleEvent>[],
    );
  }

  @override
  Future<bool> isRestrictionSessionActiveNow() async => true;

  @override
  Future<void> pauseEnforcement(Duration duration) async {
    pauseEnforcementCalled = true;
  }

  @override
  Future<void> removeMode(String modeId) async {
    removeModeCalled = true;
    calls.add('removeMode:$modeId');
  }

  @override
  Future<void> resumeEnforcement() async {
    resumeEnforcementCalled = true;
  }

  @override
  Future<void> endSession() async {
    endSessionCalled = true;
    calls.add('endSession');
  }

  @override
  Future<void> ackLifecycleEvents({required String throughEventId}) async {
    ackLifecycleEventsCalled = true;
    calls.add('ackLifecycleEvents:$throughEventId');
  }

  @override
  Future<void> setModesEnabled(bool enabled) async {
    setModesEnabledCalled = true;
    calls.add('setModesEnabled:$enabled');
  }

  @override
  Future<void> startSession(RestrictionMode mode, {Duration? duration}) async {
    startSessionCalled = true;
    startSessionDuration = duration;
    calls.add('startSession:${mode.modeId}');
  }

  @override
  Future<void> upsertMode(RestrictionMode mode) async {
    upsertModeCalled = true;
    calls.add('upsertMode:${mode.modeId}');
  }
}
