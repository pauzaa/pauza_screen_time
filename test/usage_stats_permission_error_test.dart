import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/cancel_token.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/usage_stats/data/usage_stats_manager.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_usage_stats.dart';
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
    required int startTimeMs,
    required int endTimeMs,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'Usage Access is missing');
  }

  @override
  Future<List<UsageStats>> queryUsageStats({
    required int startTimeMs,
    required int endTimeMs,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    throw PlatformException(code: 'MISSING_PERMISSION', message: 'Usage Access is missing');
  }
}
