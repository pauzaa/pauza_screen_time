import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/cancel_token.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/usage_stats/data/usage_stats_manager.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_standby_bucket.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_usage_stats.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/event_stats.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/usage_event.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/usage_stats_interval.dart';
import 'package:pauza_screen_time/src/features/usage_stats/usage_stats_platform.dart';

void main() {
  group('UsageStatsManager permission errors', () {
    test('getUsageStats throws typed missing-permission error', () async {
      final manager = UsageStatsManager(platform: _MissingPermissionPlatform());
      final now = DateTime.now();

      await expectLater(
        manager.getUsageStats(startDate: now.subtract(const Duration(days: 1)), endDate: now),
        throwsA(isA<PauzaMissingPermissionError>()),
      );
    }, skip: !Platform.isAndroid);

    test('getAppUsageStats throws typed missing-permission error', () async {
      final manager = UsageStatsManager(platform: _MissingPermissionPlatform());
      final now = DateTime.now();

      await expectLater(
        manager.getAppUsageStats(
          packageId: 'com.example.app',
          startDate: now.subtract(const Duration(days: 1)),
          endDate: now,
        ),
        throwsA(isA<PauzaMissingPermissionError>()),
      );
    }, skip: !Platform.isAndroid);
  });
}

class _MissingPermissionPlatform extends UsageStatsPlatform {
  @override
  Future<UsageStats?> queryAppUsageStats({
    required String packageId,
    required DateTime startTime,
    required DateTime endTime,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'Usage Access is missing');
  }

  @override
  Future<List<UsageStats>> queryUsageStats({
    required DateTime startTime,
    required DateTime endTime,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'Usage Access is missing');
  }

  @override
  Future<List<UsageEvent>> queryUsageEvents({
    required DateTime startTime,
    required DateTime endTime,
    List<UsageEventType>? eventTypes,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 60),
  }) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'Usage Access is missing');
  }

  @override
  Future<List<DeviceEventStats>> queryEventStats({
    required DateTime startTime,
    required DateTime endTime,
    UsageStatsInterval intervalType = UsageStatsInterval.best,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'Usage Access is missing');
  }

  @override
  Future<bool> isAppInactive({
    required String packageId,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'Usage Access is missing');
  }

  @override
  Future<AppStandbyBucket> getAppStandbyBucket({
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'Usage Access is missing');
  }
}
