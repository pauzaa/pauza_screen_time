import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/cancel_token.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';
import 'package:pauza_screen_time/src/features/installed_apps/data/installed_apps_manager.dart';
import 'package:pauza_screen_time/src/features/installed_apps/installed_apps_platform.dart';
import 'package:pauza_screen_time/src/features/installed_apps/model/app_info.dart';
import 'package:pauza_screen_time/src/features/usage_stats/data/usage_stats_manager.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_usage_stats.dart';
import 'package:pauza_screen_time/src/features/usage_stats/usage_stats_platform.dart';

void main() {
  group('InstalledAppsManager decode failures', () {
    test('getAndroidInstalledApps throws typed internal failure on malformed item', () async {
      final manager = InstalledAppsManager(platform: _MalformedInstalledApps());

      await expectLater(manager.getAndroidInstalledApps(), throwsA(isA<PauzaInternalFailureError>()));
    }, skip: !Platform.isAndroid);
  });

  group('UsageStatsManager decode failures', () {
    test('getUsageStats throws typed internal failure on malformed item', () async {
      final manager = UsageStatsManager(platform: _MalformedUsageStatsPlatform());
      final now = DateTime.now();

      await expectLater(
        manager.getUsageStats(startDate: now.subtract(const Duration(days: 1)), endDate: now),
        throwsA(isA<PauzaInternalFailureError>()),
      );
    }, skip: !Platform.isAndroid);
  });
}

class _MalformedInstalledApps extends InstalledAppsPlatform {
  @override
  Future<List<AppInfo>> getInstalledApps(
    bool includeSystemApps, {
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    throw PlatformException(code: 'INTERNAL_FAILURE', message: 'Failed to decode installed apps payload');
  }

  @override
  Future<AppInfo?> getAppInfo(
    String packageId, {
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    return null;
  }

  @override
  Future<List<IOSAppInfo>> showFamilyActivityPicker({List<String>? preSelectedTokens}) async {
    return const [];
  }
}

class _MalformedUsageStatsPlatform extends UsageStatsPlatform {
  @override
  Future<UsageStats?> queryAppUsageStats({
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
  Future<List<UsageStats>> queryUsageStats({
    required int startTimeMs,
    required int endTimeMs,
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    throw PlatformException(code: 'INTERNAL_FAILURE', message: 'Failed to decode usage stats payload');
  }
}
