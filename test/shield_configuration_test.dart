import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/background_blur_style.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/shield_configuration.dart';

void main() {
  group('ShieldConfiguration.fromMap / toMap round-trip', () {
    test('round-trips all scalar fields', () {
      const original = ShieldConfiguration(title: 'Blocked', subtitle: 'Go focus.', primaryButtonLabel: 'OK');

      final map = original.toMap();
      final restored = ShieldConfiguration.fromMap(Map<String, dynamic>.from(map));

      expect(restored.title, 'Blocked');
      expect(restored.subtitle, 'Go focus.');
      expect(restored.backgroundColor.toARGB32(), original.backgroundColor.toARGB32());
      expect(restored.titleColor.toARGB32(), original.titleColor.toARGB32());
      expect(restored.primaryButtonLabel, 'OK');
      expect(restored.iconBytes, isNull);
      expect(restored.appGroupId, isNull);
    });

    test('round-trips null optional fields', () {
      const original = ShieldConfiguration(title: 'Test');
      final map = original.toMap();
      final restored = ShieldConfiguration.fromMap(Map<String, dynamic>.from(map));

      expect(restored.subtitle, isNull);
      expect(restored.backgroundBlurStyle, isNull);
      expect(restored.primaryButtonLabel, isNull);
      expect(restored.secondaryButtonLabel, isNull);
    });

    test('fromMap falls back to default color on null backgroundColor', () {
      final map = <String, dynamic>{'title': 'Test'};
      final config = ShieldConfiguration.fromMap(map);
      // Default is black
      expect(config.backgroundColor, const Color(0xFF000000));
    });

    test('fromMap parses backgroundBlurStyle', () {
      final map = <String, dynamic>{'title': 'T', 'backgroundBlurStyle': 'dark'};
      final config = ShieldConfiguration.fromMap(map);
      expect(config.backgroundBlurStyle, BackgroundBlurStyle.dark);
    });
  });
}
