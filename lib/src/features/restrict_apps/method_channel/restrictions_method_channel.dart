import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pauza_screen_time/src/core/background_channel_runner.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/core/platform_constants.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/app_restriction_platform.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/channel_name.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/method_names.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_lifecycle_event.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_modes_config.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_state.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/shield_configuration.dart';

/// Method-channel implementation for the Restrict Apps feature.
class RestrictionsMethodChannel extends AppRestrictionPlatform {
  @visibleForTesting
  final MethodChannel channel;

  RestrictionsMethodChannel({MethodChannel? channel})
    : channel = channel ?? const MethodChannel(restrictionsChannelName);

  @override
  Future<void> configureShield(ShieldConfiguration configuration) {
    return channel.invokeMethod<void>(RestrictionsMethodNames.configureShield, configuration.toMap());
  }

  @override
  Future<void> upsertMode(RestrictionMode mode) {
    return channel.invokeMethod<void>(RestrictionsMethodNames.upsertMode, mode.toMap());
  }

  @override
  Future<void> removeMode(String modeId) {
    return channel.invokeMethod<void>(RestrictionsMethodNames.removeMode, {'modeId': modeId});
  }

  @override
  Future<void> setModesEnabled(bool enabled) {
    return channel.invokeMethod<void>(RestrictionsMethodNames.setModesEnabled, {'enabled': enabled});
  }

  @override
  Future<RestrictionModesConfig> getModesConfig() async {
    final result = await channel.invokeMethod<Map<dynamic, dynamic>>(RestrictionsMethodNames.getModesConfig);
    if (result == null) {
      throw _decodeFailure(
        action: RestrictionsMethodNames.getModesConfig,
        message: 'Received null modes config payload from platform',
      );
    }
    try {
      return RestrictionModesConfig.fromMap(Map<String, dynamic>.from(result));
    } on PlatformException {
      rethrow;
    } catch (error, stackTrace) {
      throw _decodeFailure(
        action: RestrictionsMethodNames.getModesConfig,
        message: 'Failed to decode modes config payload',
        payload: result,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<bool> isRestrictionSessionActiveNow() async {
    final result = await channel.invokeMethod<bool>(RestrictionsMethodNames.isRestrictionSessionActiveNow);
    if (result == null) {
      throw _decodeFailure(
        action: RestrictionsMethodNames.isRestrictionSessionActiveNow,
        message: 'Received null boolean from platform',
      );
    }
    return result;
  }

  @override
  Future<void> pauseEnforcement(Duration duration) {
    return channel.invokeMethod<void>(RestrictionsMethodNames.pauseEnforcement, {
      'durationMs': duration.inMilliseconds,
    });
  }

  @override
  Future<void> resumeEnforcement() {
    return channel.invokeMethod<void>(RestrictionsMethodNames.resumeEnforcement);
  }

  @override
  Future<void> startSession(RestrictionMode mode, {Duration? duration}) {
    return channel.invokeMethod<void>(RestrictionsMethodNames.startSession, {
      ...mode.toMap(),
      if (duration != null) 'durationMs': duration.inMilliseconds,
    });
  }

  @override
  Future<void> endSession({Duration? duration, RestrictionLifecycleReason? reason}) {
    final args = <String, Object?>{
      if (duration != null) 'durationMs': duration.inMilliseconds,
      if (reason != null) 'reason': reason.wireValue,
    };
    return channel.invokeMethod<void>(
      RestrictionsMethodNames.endSession,
      args.isEmpty ? null : args,
    );
  }

  @override
  Future<List<RestrictionLifecycleEvent>> getPendingLifecycleEvents({
    int limit = PlatformConstants.defaultLifecycleEventsLimit,
  }) async {
    final result = await BackgroundChannelRunner.invokeMethod<List<dynamic>>(
      channel.name,
      RestrictionsMethodNames.getPendingLifecycleEvents,
      arguments: {'limit': limit},
    );
    if (result == null) {
      return const <RestrictionLifecycleEvent>[];
    }
    try {
      return result
          .map((value) => RestrictionLifecycleEvent.fromMap(Map<String, dynamic>.from(value as Map)))
          .toList(growable: false);
    } on PlatformException {
      rethrow;
    } catch (error, stackTrace) {
      throw _decodeFailure(
        action: RestrictionsMethodNames.getPendingLifecycleEvents,
        message: 'Failed to decode lifecycle events payload',
        payload: result,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> ackLifecycleEvents({required String throughEventId}) {
    return channel.invokeMethod<void>(RestrictionsMethodNames.ackLifecycleEvents, {'throughEventId': throughEventId});
  }

  @override
  Future<RestrictionState> getRestrictionSession() async {
    final result = await channel.invokeMethod<Map<dynamic, dynamic>>(RestrictionsMethodNames.getRestrictionSession);
    if (result == null) {
      throw _decodeFailure(
        action: RestrictionsMethodNames.getRestrictionSession,
        message: 'Received null restriction session payload from platform',
      );
    }

    try {
      final normalized = Map<String, dynamic>.from(result);
      return RestrictionState.fromMap(normalized);
    } on PlatformException {
      rethrow;
    } catch (error, stackTrace) {
      throw _decodeFailure(
        action: RestrictionsMethodNames.getRestrictionSession,
        message: 'Failed to decode restriction session payload',
        payload: result,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  PauzaInternalFailureError _decodeFailure({
    required String action,
    required String message,
    Object? payload,
    Object? error,
    StackTrace? stackTrace,
  }) {
    return PauzaInternalFailureError(
      message: message,
      rawCode: 'INTERNAL_FAILURE',
      details: <String, Object?>{
        'feature': 'restrictions',
        'action': action,
        'platform': 'dart',
        if (payload != null) 'payloadType': payload.runtimeType.toString(),
        if (error != null) 'errorType': error.runtimeType.toString(),
        if (error != null || stackTrace != null)
          'diagnostic': [if (error != null) error.toString(), if (stackTrace != null) stackTrace.toString()].join('\n'),
      },
    );
  }
}
