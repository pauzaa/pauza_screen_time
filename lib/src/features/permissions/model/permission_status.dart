/// Permission status and types for the plugin.
///
/// This module defines the possible states of permissions
/// across both Android and iOS platforms.
library;

/// Status of a permission.
enum PermissionStatus {
  /// Permission has been granted.
  granted,

  /// Permission has been denied by the user.
  denied,

  /// Permission is restricted and cannot be granted (e.g., parental controls).
  restricted,

  /// Permission status has not been determined yet (iOS specific).
  /// User has not been asked for this permission.
  notDetermined;

  /// Whether the permission is granted.
  bool get isGranted => this == PermissionStatus.granted;

  /// Whether the permission is denied but can be requested again.
  bool get isDenied => this == PermissionStatus.denied;

  /// Whether the permission is permanently restricted.
  bool get isRestricted => this == PermissionStatus.restricted;

  /// Whether the permission has not been determined yet.
  bool get isNotDetermined => this == PermissionStatus.notDetermined;

  /// Whether the permission can be requested.
  /// True if status is denied or notDetermined.
  bool get canRequest => this == PermissionStatus.denied || this == PermissionStatus.notDetermined;

  /// Creates a PermissionStatus from its string representation.
  ///
  /// Throws [ArgumentError] if the value is not recognized.
  factory PermissionStatus.fromString(String value) {
    switch (value.toLowerCase()) {
      case 'granted':
        return PermissionStatus.granted;
      case 'denied':
        return PermissionStatus.denied;
      case 'restricted':
        return PermissionStatus.restricted;
      case 'unknown':
      case 'notdetermined':
      case 'not_determined':
        return PermissionStatus.notDetermined;
      default:
        throw ArgumentError('Unknown permission status: $value');
    }
  }
}
