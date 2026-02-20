/// iOS-specific permissions required by the plugin.
///
/// This enum represents permissions specific to the iOS platform
/// for Screen Time API and Family Controls functionality.
library;

/// iOS platform permissions.
enum IOSPermission {
  /// Permission to use Family Controls framework.
  /// Required for all Screen Time API functionality.
  /// Requires user authorization and Family Sharing setup.
  familyControls(
    key: 'ios.familyControls',
    displayName: 'Family Controls',
    description: 'Required to manage app restrictions and parental controls',
  ),

  /// Permission to access Screen Time data.
  /// Includes usage statistics and app activity monitoring.
  screenTime(
    key: 'ios.screenTime',
    displayName: 'Screen Time',
    description: 'Required to access app usage statistics and screen time data',
  );

  const IOSPermission({required this.key, required this.displayName, required this.description});

  /// The string key for platform channel communication.
  final String key;

  /// A user-friendly name for the permission.
  final String displayName;

  /// A description of what the permission is used for.
  final String description;

  /// Creates an IOSPermission from its string key.
  factory IOSPermission.fromKey(String key) {
    return IOSPermission.values.firstWhere(
      (element) => element.key == key,
      orElse: () => throw ArgumentError('Unknown iOS permission key: $key'),
    );
  }
}
