import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/cancel_token.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/installed_apps/data/installed_apps_manager.dart';
import 'package:pauza_screen_time/src/features/installed_apps/installed_apps_platform.dart';
import 'package:pauza_screen_time/src/features/usage_stats/data/usage_stats_manager.dart';
import 'package:pauza_screen_time/src/features/usage_stats/usage_stats_platform.dart';

void main() {
  group('InstalledAppsManager decode failures', () {
    test(
      'getAndroidInstalledApps throws typed internal failure on malformed item',
      () async {
        final manager = InstalledAppsManager(
          platform: _MalformedInstalledApps(),
        );

        await expectLater(
          manager.getAndroidInstalledApps(),
          throwsA(isA<PauzaInternalFailureError>()),
        );
      },
      skip: !Platform.isAndroid,
    );
  });

  group('UsageStatsManager decode failures', () {
    test(
      'getUsageStats throws typed internal failure on malformed item',
      () async {
        final manager = UsageStatsManager(
          platform: _MalformedUsageStatsPlatform(),
        );
        final now = DateTime.now();

        await expectLater(
          manager.getUsageStats(
            startDate: now.subtract(const Duration(days: 1)),
            endDate: now,
          ),
          throwsA(isA<PauzaInternalFailureError>()),
        );
      },
      skip: !Platform.isAndroid,
    );
  });
}

class _MalformedInstalledApps extends InstalledAppsPlatform {
  @override
  Future<List<Map<dynamic, dynamic>>> getInstalledApps(
    bool includeSystemApps, {
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return const [
      {'platform': 'android', 'name': 'Missing package id'},
    ];
  }

  @override
  Future<Map<dynamic, dynamic>?> getAppInfo(
    String packageId, {
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return null;
  }

  @override
  Future<List<Map<dynamic, dynamic>>> showFamilyActivityPicker({
    List<String>? preSelectedTokens,
  }) async {
    return const [];
  }
}

class _MalformedUsageStatsPlatform extends UsageStatsPlatform {
  @override
  Future<Map<dynamic, dynamic>?> queryAppUsageStats({
    required String packageId,
    required int startTimeMs,
    required int endTimeMs,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return null;
  }

  @override
  Future<List<Map<dynamic, dynamic>>> queryUsageStats({
    required int startTimeMs,
    required int endTimeMs,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return const [
      {
        'packageId': 'com.example.bad',
        'appName': 'Broken',
        'totalDurationMs': 'bad',
        'totalLaunchCount': 1,
      },
    ];
  }
}
