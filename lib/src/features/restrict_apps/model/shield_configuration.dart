import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/background_blur_style.dart';

/// Configuration for the native blocking shield displayed over restricted apps.
@immutable
class ShieldConfiguration {
  /// iOS App Group identifier used to persist/read shield settings.
  ///
  /// Optional and **iOS-only**. When provided, the native iOS implementation can
  /// store configuration into the specified App Group so it can be accessed by
  /// related extensions (e.g. a Shield extension).
  final String? appGroupId;

  /// Main title text displayed on the shield.
  final String title;

  /// Optional subtitle text displayed below the title.
  final String? subtitle;

  /// Background color of the shield.
  final Color backgroundColor;

  /// Color of the title text.
  final Color titleColor;

  /// Color of the subtitle text.
  final Color subtitleColor;

  /// Background blur effect applied behind the shield.
  /// If null, no blur effect is applied.
  /// Maps to UIBlurEffect.Style on iOS and RenderEffect on Android (12+).
  final BackgroundBlurStyle? backgroundBlurStyle;

  /// Custom icon to display on the shield (PNG bytes).
  /// If null, a default icon may be shown.
  final Uint8List? iconBytes;

  /// Label for the primary action button.
  /// If null, no primary button is shown.
  final String? primaryButtonLabel;

  /// Background color of the primary button.
  final Color? primaryButtonBackgroundColor;

  /// Text color of the primary button.
  final Color? primaryButtonTextColor;

  /// Label for the secondary action button.
  /// If null, no secondary button is shown.
  final String? secondaryButtonLabel;

  /// Text color of the secondary button.
  final Color? secondaryButtonTextColor;

  const ShieldConfiguration({
    required this.title,
    this.appGroupId,
    this.subtitle,
    this.backgroundColor = const Color(0xFF000000),
    this.titleColor = const Color(0xFFFFFFFF),
    this.subtitleColor = const Color(0xFFFFFFFF),
    this.backgroundBlurStyle,
    this.iconBytes,
    this.primaryButtonLabel,
    this.primaryButtonBackgroundColor,
    this.primaryButtonTextColor,
    this.secondaryButtonLabel,
    this.secondaryButtonTextColor,
  });

  /// Creates a [ShieldConfiguration] from a platform-channel map.
  factory ShieldConfiguration.fromMap(Map<String, dynamic> map) {
    return ShieldConfiguration(
      appGroupId: map['appGroupId'] as String?,
      title: map['title'] as String? ?? 'App Blocked',
      subtitle: map['subtitle'] as String?,
      backgroundColor: _colorFromArgb32(map['backgroundColor']),
      titleColor: _colorFromArgb32(map['titleColor']),
      subtitleColor: _colorFromArgb32(map['subtitleColor']),
      backgroundBlurStyle: BackgroundBlurStyle.fromValue(map['backgroundBlurStyle'] as String?),
      iconBytes: map['iconBytes'] as Uint8List?,
      primaryButtonLabel: map['primaryButtonLabel'] as String?,
      primaryButtonBackgroundColor: _colorFromArgb32Nullable(map['primaryButtonBackgroundColor']),
      primaryButtonTextColor: _colorFromArgb32Nullable(map['primaryButtonTextColor']),
      secondaryButtonLabel: map['secondaryButtonLabel'] as String?,
      secondaryButtonTextColor: _colorFromArgb32Nullable(map['secondaryButtonTextColor']),
    );
  }

  static Color _colorFromArgb32(Object? value) {
    final argb = switch (value) {
      final int v => v,
      final num v => v.toInt(),
      _ => 0xFF000000,
    };
    return Color(argb);
  }

  static Color? _colorFromArgb32Nullable(Object? value) {
    if (value == null) return null;
    return _colorFromArgb32(value);
  }

  /// Converts this configuration to a map for platform channel serialization.

  Map<String, dynamic> toMap() {
    return {
      'appGroupId': appGroupId,
      'title': title,
      'subtitle': subtitle,
      'backgroundColor': backgroundColor.toARGB32(),
      'titleColor': titleColor.toARGB32(),
      'subtitleColor': subtitleColor.toARGB32(),
      'backgroundBlurStyle': backgroundBlurStyle?.value,
      'iconBytes': iconBytes,
      'primaryButtonLabel': primaryButtonLabel,
      'primaryButtonBackgroundColor': primaryButtonBackgroundColor?.toARGB32(),
      'primaryButtonTextColor': primaryButtonTextColor?.toARGB32(),
      'secondaryButtonLabel': secondaryButtonLabel,
      'secondaryButtonTextColor': secondaryButtonTextColor?.toARGB32(),
    };
  }

  /// Creates a new ShieldConfiguration with some values replaced.
  ShieldConfiguration copyWith({
    String? appGroupId,
    String? title,
    String? subtitle,
    Color? backgroundColor,
    Color? titleColor,
    Color? subtitleColor,
    BackgroundBlurStyle? backgroundBlurStyle,
    Uint8List? iconBytes,
    String? primaryButtonLabel,
    Color? primaryButtonBackgroundColor,
    Color? primaryButtonTextColor,
    String? secondaryButtonLabel,
    Color? secondaryButtonTextColor,
  }) {
    return ShieldConfiguration(
      appGroupId: appGroupId ?? this.appGroupId,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      titleColor: titleColor ?? this.titleColor,
      subtitleColor: subtitleColor ?? this.subtitleColor,
      backgroundBlurStyle: backgroundBlurStyle ?? this.backgroundBlurStyle,
      iconBytes: iconBytes ?? this.iconBytes,
      primaryButtonLabel: primaryButtonLabel ?? this.primaryButtonLabel,
      primaryButtonBackgroundColor: primaryButtonBackgroundColor ?? this.primaryButtonBackgroundColor,
      primaryButtonTextColor: primaryButtonTextColor ?? this.primaryButtonTextColor,
      secondaryButtonLabel: secondaryButtonLabel ?? this.secondaryButtonLabel,
      secondaryButtonTextColor: secondaryButtonTextColor ?? this.secondaryButtonTextColor,
    );
  }
}
