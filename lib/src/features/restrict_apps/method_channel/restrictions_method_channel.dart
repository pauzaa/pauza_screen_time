import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:pauza_screen_time/src/core/app_identifier.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/app_restriction_platform.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/channel_name.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/method_channel/method_names.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_scheduled_mode.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_scheduled_modes_config.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_session.dart';

/// Method-channel implementation for the Restrict Apps feature.
class RestrictionsMethodChannel extends AppRestrictionPlatform {
  @visibleForTesting
  final MethodChannel channel;

  RestrictionsMethodChannel({MethodChannel? channel})
    : channel = channel ?? const MethodChannel(restrictionsChannelName);

  @override
  Future<void> configureShield(Map<String, dynamic> configuration) {
    return channel.invokeMethod<void>(
      RestrictionsMethodNames.configureShield,
      configuration,
    );
  }

  @override
  Future<List<AppIdentifier>> setRestrictedApps(
    List<AppIdentifier> identifiers,
  ) async {
    final result = await channel.invokeMethod<List<dynamic>>(
      RestrictionsMethodNames.setRestrictedApps,
      {
        'identifiers': identifiers
            .map((identifier) => identifier.value)
            .toList(),
      },
    );
    if (result == null) return [];
    return result.cast<String>().map(AppIdentifier.new).toList();
  }

  @override
  Future<bool> addRestrictedApp(AppIdentifier identifier) async {
    final result = await channel.invokeMethod<bool>(
      RestrictionsMethodNames.addRestrictedApp,
      {'identifier': identifier.value},
    );
    return result ?? false;
  }

  @override
  Future<bool> removeRestriction(AppIdentifier identifier) async {
    final result = await channel.invokeMethod<bool>(
      RestrictionsMethodNames.removeRestriction,
      {'identifier': identifier.value},
    );
    return result ?? false;
  }

  @override
  Future<bool> isRestricted(AppIdentifier identifier) async {
    final result = await channel.invokeMethod<bool>(
      RestrictionsMethodNames.isRestricted,
      {'identifier': identifier.value},
    );
    return result ?? false;
  }

  @override
  Future<void> removeAllRestrictions() {
    return channel.invokeMethod<void>(
      RestrictionsMethodNames.removeAllRestrictions,
    );
  }

  @override
  Future<List<AppIdentifier>> getRestrictedApps() async {
    final result = await channel.invokeMethod<List<dynamic>>(
      RestrictionsMethodNames.getRestrictedApps,
    );
    if (result == null) return [];
    return result.cast<String>().map(AppIdentifier.new).toList();
  }

  @override
  Future<bool> isRestrictionSessionActiveNow() async {
    final result = await channel.invokeMethod<bool>(
      RestrictionsMethodNames.isRestrictionSessionActiveNow,
    );
    return result ?? false;
  }

  @override
  Future<bool> isRestrictionSessionConfigured() async {
    final result = await channel.invokeMethod<bool>(
      RestrictionsMethodNames.isRestrictionSessionConfigured,
    );
    return result ?? false;
  }

  @override
  Future<void> pauseEnforcement(Duration duration) {
    return channel.invokeMethod<void>(
      RestrictionsMethodNames.pauseEnforcement,
      {'durationMs': duration.inMilliseconds},
    );
  }

  @override
  Future<void> resumeEnforcement() {
    return channel.invokeMethod<void>(
      RestrictionsMethodNames.resumeEnforcement,
    );
  }

  @override
  Future<void> startRestrictionSession() {
    return channel.invokeMethod<void>(
      RestrictionsMethodNames.startRestrictionSession,
    );
  }

  @override
  Future<void> endRestrictionSession() {
    return channel.invokeMethod<void>(
      RestrictionsMethodNames.endRestrictionSession,
    );
  }

  @override
  Future<RestrictionSession> getRestrictionSession() async {
    final result = await channel.invokeMethod<Map<dynamic, dynamic>>(
      RestrictionsMethodNames.getRestrictionSession,
    );
    if (result == null) {
      throw _decodeFailure(
        action: RestrictionsMethodNames.getRestrictionSession,
        message: 'Received null restriction session payload from platform',
      );
    }

    try {
      final normalized = Map<String, dynamic>.from(result);
      return RestrictionSession.fromMap(normalized);
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

  @override
  Future<void> upsertScheduledMode(RestrictionScheduledMode mode) {
    return channel.invokeMethod<void>(
      RestrictionsMethodNames.upsertScheduledMode,
      mode.toMap(),
    );
  }

  @override
  Future<void> removeScheduledMode(String modeId) {
    return channel.invokeMethod<void>(
      RestrictionsMethodNames.removeScheduledMode,
      {'modeId': modeId},
    );
  }

  @override
  Future<void> setScheduledModesEnabled(bool enabled) {
    return channel.invokeMethod<void>(
      RestrictionsMethodNames.setScheduledModesEnabled,
      {'enabled': enabled},
    );
  }

  @override
  Future<RestrictionScheduledModesConfig> getScheduledModesConfig() async {
    final result = await channel.invokeMethod<Map<dynamic, dynamic>>(
      RestrictionsMethodNames.getScheduledModesConfig,
    );
    if (result == null) {
      throw _decodeFailure(
        action: RestrictionsMethodNames.getScheduledModesConfig,
        message: 'Received null scheduled modes config payload from platform',
      );
    }
    try {
      return RestrictionScheduledModesConfig.fromMap(
        Map<String, dynamic>.from(result),
      );
    } on PlatformException {
      rethrow;
    } catch (error, stackTrace) {
      throw _decodeFailure(
        action: RestrictionsMethodNames.getScheduledModesConfig,
        message: 'Failed to decode scheduled modes config payload',
        payload: result,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  PlatformException _decodeFailure({
    required String action,
    required String message,
    Object? payload,
    Object? error,
    StackTrace? stackTrace,
  }) {
    return PlatformException(
      code: 'INTERNAL_FAILURE',
      message: message,
      details: <String, Object?>{
        'feature': 'restrictions',
        'action': action,
        'platform': 'dart',
        if (payload != null) 'payloadType': payload.runtimeType.toString(),
        if (error != null) 'errorType': error.runtimeType.toString(),
        if (error != null || stackTrace != null)
          'diagnostic': [
            if (error != null) error.toString(),
            if (stackTrace != null) stackTrace.toString(),
          ].join('\n'),
      },
    );
  }
}
