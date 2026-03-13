import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/core.dart';
import 'package:pauza_screen_time/src/features/installed_apps/data/installed_apps_manager.dart';
import 'package:pauza_screen_time/src/features/installed_apps/installed_apps_platform.dart';
import 'package:pauza_screen_time/src/features/installed_apps/model/app_info.dart';
import 'package:pauza_screen_time/src/features/usage_stats/data/usage_stats_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InstalledAppsManager decode failures', () {
    test('getAndroidInstalledApps throws typed internal failure on malformed item', () async {
      final manager = InstalledAppsManager(platform: _MalformedInstalledApps());

      if (!Platform.isAndroid) {
        await expectLater(manager.getAndroidInstalledApps(), throwsA(isA<PauzaUnsupportedError>()));
        return;
      }

      await expectLater(manager.getAndroidInstalledApps(), throwsA(isA<PauzaInternalFailureError>()));
    });
  });

  group('UsageStatsManager decode failures', () {
    test('getUsageStats throws typed internal failure on malformed item', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('pauza_screen_time/usage_stats'),
        (call) async => [
          {'malformed': 'data'},
        ],
      );

      final manager = UsageStatsManager();
      final now = DateTime.now();

      if (!Platform.isAndroid) {
        await expectLater(
          manager.getUsageStats(startDate: now.subtract(const Duration(days: 1)), endDate: now),
          throwsA(isA<PauzaUnsupportedError>()),
        );
        return;
      }

      await expectLater(
        manager.getUsageStats(startDate: now.subtract(const Duration(days: 1)), endDate: now),
        throwsA(isA<PauzaInternalFailureError>()),
      );
    });
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
    return [const IOSAppInfo(applicationToken: AppIdentifier.ios('token1'))];
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
