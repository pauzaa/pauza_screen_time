/// Opaque app identifier wrapper used by cross-platform restriction APIs.
///
/// - Android: package identifier (for example, `com.whatsapp`)
/// - iOS: base64-encoded `ApplicationToken` from FamilyActivityPicker
extension type const AppIdentifier(String value) {
  const AppIdentifier.android(String packageId) : value = packageId;
  const AppIdentifier.ios(String applicationTokenBase64) : value = applicationTokenBase64;

  String get raw => value;
}
