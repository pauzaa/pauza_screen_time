import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:pauza_screen_time/src/core/cancel_token.dart';
import 'package:pauza_screen_time/src/features/installed_apps/model/app_info.dart';

/// Platform interface for installed apps functionality.
///
/// Defines the contract for platform-specific implementations
/// of app enumeration and information retrieval.
abstract class InstalledAppsPlatform extends PlatformInterface {
  InstalledAppsPlatform() : super(token: _token);

  static final Object _token = Object();

  /// Returns a list of all installed applications.
  ///
  /// [includeSystemApps] - Whether to include system apps.
  /// [includeIcons] - Whether to include app icons (default: true).
  Future<List<AppInfo>> getInstalledApps(
    bool includeSystemApps, {
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) {
    throw UnimplementedError('getInstalledApps() has not been implemented.');
  }

  /// Returns information about a specific app.
  ///
  /// Returns null if the app is not found.
  /// [includeIcons] - Whether to include app icons (default: true).
  Future<AppInfo?> getAppInfo(
    String packageId, {
    bool includeIcons = true,
    CancelToken? cancelToken,
    Duration timeout = const Duration(seconds: 30),
  }) {
    throw UnimplementedError('getAppInfo() has not been implemented.');
  }

  /// Shows the iOS FamilyActivityPicker for user to select apps.
  ///
  /// [preSelectedTokens] - Optional list of base64-encoded ApplicationTokens
  /// that should appear pre-selected when the picker opens.
  ///
  /// Only available on iOS.
  Future<List<IOSAppInfo>> showFamilyActivityPicker({List<String>? preSelectedTokens}) {
    throw UnimplementedError('showFamilyActivityPicker() has not been implemented.');
  }
}
