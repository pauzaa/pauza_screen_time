import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/features/permissions/data/permission_helper.dart';
import 'package:pauza_screen_time/src/features/permissions/data/permission_manager.dart';
import 'package:pauza_screen_time/src/features/permissions/method_channel/channel_name.dart';
import 'package:pauza_screen_time/src/features/permissions/method_channel/method_names.dart';
import 'package:pauza_screen_time/src/features/permissions/model/android_permission.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(permissionsChannelName);

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('AndroidPermission.fromKey resolves exact alarm key', () {
    expect(
      AndroidPermission.fromKey('android.exactAlarm'),
      AndroidPermission.exactAlarm,
    );
  });

  test(
    'PermissionHelper requests exact alarm when usage/accessibility are granted',
    () async {
      final requested = <String>[];
      _setPermissionsHandler(
        channel: channel,
        onCheckPermission: (permissionKey) {
          if (permissionKey == AndroidPermission.exactAlarm.key) {
            return 'denied';
          }
          return 'granted';
        },
        onRequestPermission: (permissionKey) {
          requested.add(permissionKey);
          return true;
        },
      );

      final helper = PermissionHelper(PermissionManager());
      await helper.requestAllRequiredPermissions();

      expect(requested, [AndroidPermission.exactAlarm.key]);
    },
    skip: !Platform.isAndroid,
  );

  test(
    'getMissingAndroidPermissions() includes exact alarm when denied',
    () async {
      _setPermissionsHandler(
        channel: channel,
        onCheckPermission: (permissionKey) {
          if (permissionKey == AndroidPermission.exactAlarm.key) {
            return 'denied';
          }
          return 'granted';
        },
        onRequestPermission: (_) => true,
      );

      final manager = PermissionManager();
      final missing = await manager.getMissingAndroidPermissions();

      expect(missing.contains(AndroidPermission.exactAlarm), isTrue);
    },
    skip: !Platform.isAndroid,
  );
}

void _setPermissionsHandler({
  required MethodChannel channel,
  required String Function(String permissionKey) onCheckPermission,
  required bool Function(String permissionKey) onRequestPermission,
}) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        final args = call.arguments as Map<dynamic, dynamic>?;
        final permissionKey = args?['permissionKey'] as String?;

        switch (call.method) {
          case PermissionsMethodNames.checkPermission:
            if (permissionKey == null) {
              return 'unknown';
            }
            return onCheckPermission(permissionKey);
          case PermissionsMethodNames.requestPermission:
            if (permissionKey == null) {
              return false;
            }
            return onRequestPermission(permissionKey);
          case PermissionsMethodNames.openPermissionSettings:
            return null;
          default:
            return null;
        }
      });
}
