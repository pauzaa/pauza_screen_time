import 'package:flutter/foundation.dart';
import 'package:pauza_screen_time/src/core/core.dart';

/// Information about an installed application on the device.
///
/// This is a sealed class with platform-specific implementations:
/// - [AndroidAppInfo] - Rich metadata from PackageManager
/// - [IOSAppInfo] - Opaque token from FamilyActivityPicker
///
/// Platform-specific behavior is enforced at compile-time through
/// exhaustive pattern matching.
@immutable
sealed class AppInfo {
  const AppInfo();

  /// Creates an AppInfo from a map (platform channel deserialization).
  factory AppInfo.fromMap(Map<String, dynamic> map) {
    final platform = map['platform'] as String;

    if (platform == 'android') {
      return AndroidAppInfo.fromMap(map);
    } else if (platform == 'ios') {
      return IOSAppInfo.fromMap(map);
    } else {
      throw ArgumentError('Unknown platform: $platform');
    }
  }

  /// Converts this AppInfo to a map (for database/platform serialization).
  Map<String, dynamic> toMap();

  /// Returns a common identifier that can be used as a key.
  /// - Android: Returns packageId
  /// - iOS: Returns base64-encoded token
  AppIdentifier get identifier;
}

/// Android app information with full metadata from PackageManager.
@immutable
class AndroidAppInfo extends AppInfo {
  /// Package name (e.g., "com.whatsapp").
  final AppIdentifier packageId;

  /// Display name from PackageManager.
  final String name;

  /// App icon as PNG bytes.
  final Uint8List? icon;

  /// App category (available on Android 8.0+).
  final String? category;

  /// Whether this is a system app.
  final bool isSystemApp;

  const AndroidAppInfo({
    required this.packageId,
    required this.name,
    this.icon,
    this.category,
    this.isSystemApp = false,
  });

  /// Creates an AndroidAppInfo from a map (platform channel deserialization).
  factory AndroidAppInfo.fromMap(Map<String, dynamic> map) {
    return AndroidAppInfo(
      packageId: AppIdentifier.android(map['packageId'] as String),
      name: map['name'] as String,
      icon: map['icon'] as Uint8List?,
      category: map['category'] as String?,
      isSystemApp: map['isSystemApp'] as bool? ?? false,
    );
  }

  @override
  Map<String, dynamic> toMap() {
    return {
      'platform': 'android',
      'packageId': packageId,
      'name': name,
      'icon': icon,
      'category': category,
      'isSystemApp': isSystemApp,
    };
  }

  @override
  AppIdentifier get identifier => packageId;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AndroidAppInfo && other.packageId == packageId;
  }

  @override
  int get hashCode => packageId.hashCode;

  @override
  String toString() => 'AndroidAppInfo(packageId: $packageId, name: $name)';
}

/// iOS app information with opaque application token.
///
/// Due to iOS privacy restrictions, only the token is available.
/// Use native SwiftUI `Label(applicationToken)` to display name/icon.
@immutable
class IOSAppInfo extends AppInfo {
  /// Opaque application token (base64-encoded for serialization).
  ///
  /// This token can be:
  /// - Stored in database
  /// - Used with ManagedSettings for restrictions
  /// - Passed to native UI for display (via platform view)
  final AppIdentifier applicationToken;

  const IOSAppInfo({required this.applicationToken});

  /// Creates an IOSAppInfo from a map (platform channel deserialization).
  factory IOSAppInfo.fromMap(Map<String, dynamic> map) {
    return IOSAppInfo(applicationToken: AppIdentifier.ios(map['applicationToken'] as String));
  }

  @override
  Map<String, dynamic> toMap() {
    return {'platform': 'ios', 'applicationToken': applicationToken};
  }

  @override
  AppIdentifier get identifier => applicationToken;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IOSAppInfo && other.applicationToken == applicationToken;
  }

  @override
  int get hashCode => applicationToken.hashCode;

  @override
  String toString() =>
      'IOSAppInfo(token: ${applicationToken.raw.length > 20 ? applicationToken.raw.substring(0, 20) : applicationToken.raw}...)';
}
