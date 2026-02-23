import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pauza_screen_time/src/core/core.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Extracts a required [String] field from a raw channel map.
///
/// Throws [PauzaInternalFailureError] if the field is absent or not a [String].
String _requireString(Map<String, dynamic> map, String key, String context) {
  final value = map[key];
  if (value is String) return value;
  throw PauzaError.fromPlatformException(
        PlatformException(
          code: 'INTERNAL_FAILURE',
          message: '$context: field "$key" must be a non-null String, got ${value?.runtimeType}',
          details: <String, Object?>{'feature': 'installed_apps', 'platform': 'dart', 'field': key},
        ),
      )
      as PauzaInternalFailureError;
}

/// Extracts an optional [bool] field from a raw channel map, defaulting to [fallback].
bool _optionalBool(Map<String, dynamic> map, String key, {required bool fallback}) {
  final value = map[key];
  if (value == null) return fallback;
  if (value is bool) return value;
  return fallback;
}

// ---------------------------------------------------------------------------
// AppInfo sealed class
// ---------------------------------------------------------------------------

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
  ///
  /// Throws [PauzaInternalFailureError] when `platform` is absent, not a
  /// [String], or contains an unrecognised value.
  factory AppInfo.fromMap(Map<String, dynamic> map) {
    final platform = map['platform'];
    if (platform is! String) {
      throw PauzaError.fromPlatformException(
            PlatformException(
              code: 'INTERNAL_FAILURE',
              message: 'AppInfo.fromMap: "platform" must be a non-null String, got ${platform?.runtimeType}',
              details: <String, Object?>{'feature': 'installed_apps', 'platform': 'dart'},
            ),
          )
          as PauzaInternalFailureError;
    }

    if (platform == 'android') {
      return AndroidAppInfo.fromMap(map);
    } else if (platform == 'ios') {
      return IOSAppInfo.fromMap(map);
    } else {
      throw PauzaError.fromPlatformException(
            PlatformException(
              code: 'INTERNAL_FAILURE',
              message: 'AppInfo.fromMap: unknown platform "$platform"',
              details: <String, Object?>{'feature': 'installed_apps', 'platform': 'dart', 'received': platform},
            ),
          )
          as PauzaInternalFailureError;
    }
  }

  /// Converts this AppInfo to a map (for database/platform serialization).
  Map<String, dynamic> toMap();

  /// Returns a common identifier that can be used as a key.
  /// - Android: Returns packageId
  /// - iOS: Returns base64-encoded token
  AppIdentifier get identifier;
}

// ---------------------------------------------------------------------------
// AndroidAppInfo
// ---------------------------------------------------------------------------

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
  ///
  /// Throws [PauzaInternalFailureError] on missing or wrong-typed required fields.
  factory AndroidAppInfo.fromMap(Map<String, dynamic> map) {
    const ctx = 'AndroidAppInfo.fromMap';
    return AndroidAppInfo(
      packageId: AppIdentifier.android(_requireString(map, 'packageId', ctx)),
      name: _requireString(map, 'name', ctx),
      icon: map['icon'] as Uint8List?,
      category: map['category'] as String?,
      isSystemApp: _optionalBool(map, 'isSystemApp', fallback: false),
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

// ---------------------------------------------------------------------------
// IOSAppInfo
// ---------------------------------------------------------------------------

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
  ///
  /// Throws [PauzaInternalFailureError] on missing or wrong-typed required fields.
  factory IOSAppInfo.fromMap(Map<String, dynamic> map) {
    const ctx = 'IOSAppInfo.fromMap';
    return IOSAppInfo(applicationToken: AppIdentifier.ios(_requireString(map, 'applicationToken', ctx)));
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
