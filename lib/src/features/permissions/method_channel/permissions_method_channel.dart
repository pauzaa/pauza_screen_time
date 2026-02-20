import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:pauza_screen_time/src/features/permissions/model/permission_status.dart';
import 'package:pauza_screen_time/src/features/permissions/permission_platform.dart';
import 'package:pauza_screen_time/src/features/permissions/method_channel/channel_name.dart';
import 'package:pauza_screen_time/src/features/permissions/method_channel/method_names.dart';

/// Method-channel implementation for the Permissions feature.
class PermissionsMethodChannel extends PermissionPlatform {
  @visibleForTesting
  final MethodChannel channel;

  PermissionsMethodChannel({MethodChannel? channel}) : channel = channel ?? const MethodChannel(permissionsChannelName);

  @override
  Future<PermissionStatus> checkPermission(String permissionKey) async {
    final result = await channel.invokeMethod<String>(PermissionsMethodNames.checkPermission, {
      'permissionKey': permissionKey,
    });
    if (result == null) {
      throw StateError('Native layer returned null for permission check: $permissionKey');
    }
    return PermissionStatus.fromString(result);
  }

  @override
  Future<bool> requestPermission(String permissionKey) async {
    final result = await channel.invokeMethod<bool>(PermissionsMethodNames.requestPermission, {
      'permissionKey': permissionKey,
    });
    return result ?? false;
  }

  @override
  Future<void> openPermissionSettings(String permissionKey) {
    return channel.invokeMethod<void>(PermissionsMethodNames.openPermissionSettings, {'permissionKey': permissionKey});
  }
}
