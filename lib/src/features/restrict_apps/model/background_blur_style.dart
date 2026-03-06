/// Background blur effect styles for the shield.
///
/// Defines blur effect intensities for the shield screen
/// displayed when a restricted app is launched. Maps to
/// UIBlurEffect.Style on iOS and RenderEffect.createBlurEffect on Android.
library;

/// Background blur effect style applied behind the shield screen.
enum BackgroundBlurStyle {
  /// Extra light blur (light content on dark background).
  /// iOS: .extraLight
  extraLight('extraLight'),

  /// Light blur style.
  /// iOS: .light
  light('light'),

  /// Dark blur (dark content on light background).
  /// iOS: .dark
  dark('dark'),

  /// Regular system blur with medium intensity.
  /// iOS: .regular
  regular('regular'),

  /// Prominent blur with higher intensity for emphasis.
  /// iOS: .prominent
  prominent('prominent');

  const BackgroundBlurStyle(this.value);

  /// Platform channel serialization value.
  final String value;

  /// Creates an instance from a platform channel value.
  static BackgroundBlurStyle? fromValue(String? value) {
    if (value == null) return null;
    return BackgroundBlurStyle.values.firstWhere(
      (style) => style.value == value,
      orElse: () => BackgroundBlurStyle.regular,
    );
  }
}
