import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:pauza_screen_time/pauza_screen_time.dart';

import '../log/in_app_log.dart';

/// Snapshot of health status.
class HealthSnapshot {
  final Map<AndroidPermission, PermissionStatus> permissionStatuses;
  final List<AppIdentifier> restrictedIds;
  final DateTime updatedAt;

  HealthSnapshot({
    required this.permissionStatuses,
    required this.restrictedIds,
    required this.updatedAt,
  });

  int get restrictedCount => restrictedIds.length;

  bool get isUsageStatsGranted =>
      permissionStatuses[AndroidPermission.usageStats]?.isGranted ?? false;

  bool get isAccessibilityGranted =>
      permissionStatuses[AndroidPermission.accessibility]?.isGranted ?? false;

  bool get isQueryAllPackagesGranted =>
      permissionStatuses[AndroidPermission.queryAllPackages]?.isGranted ??
      false;
}

/// Controller for managing health status.
class HealthController extends ValueNotifier<HealthSnapshot?> {
  final PermissionManager permissionManager;
  final AppRestrictionManager restrictionManager;
  final InAppLogController logController;

  HealthController({
    required this.permissionManager,
    required this.restrictionManager,
    required this.logController,
  }) : super(null);

  Future<void> refresh() async {
    if (!Platform.isAndroid) {
      logController.warn('health', 'Health refresh skipped (Android only)');
      return;
    }

    try {
      logController.info('health', 'Refreshing health status...');

      // Check permissions
      final permissions = [
        AndroidPermission.usageStats,
        AndroidPermission.accessibility,
        AndroidPermission.queryAllPackages,
      ];
      final statuses = await permissionManager.checkAndroidPermissions(
        permissions,
      );

      // Get blocked apps from all configured modes.
      final modesConfig = await restrictionManager.getModesConfig();
      final restrictedIds = modesConfig.modes
          .expand((mode) => mode.blockedAppIds)
          .toSet()
          .toList();

      value = HealthSnapshot(
        permissionStatuses: statuses,
        restrictedIds: restrictedIds,
        updatedAt: DateTime.now(),
      );

      logController.info(
        'health',
        'Health refreshed: ${restrictedIds.length} restricted apps, '
            'Usage Access: ${statuses[AndroidPermission.usageStats]?.isGranted ?? false}, '
            'Accessibility: ${statuses[AndroidPermission.accessibility]?.isGranted ?? false}',
      );
    } catch (e, st) {
      logController.error('health', 'Failed to refresh health status', e, st);
    }
  }
}
