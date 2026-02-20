import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fresh-install manual mode contract', () {
    test('does not keep legacy manual mode fallback hooks', () {
      final root = Directory.current.path;
      final paths = <String>[
        '$root/android/src/main/kotlin/com/example/pauza_screen_time/app_restriction/RestrictionManualModeResolver.kt',
        '$root/android/src/main/kotlin/com/example/pauza_screen_time/app_restriction/RestrictionManager.kt',
        '$root/ios/Classes/AppRestriction/RestrictionStateStore.swift',
        '$root/ios/Classes/AppRestriction/MethodChannel/RestrictionsMethodHandler.swift',
        '$root/docs/templates/PauzaDeviceActivityMonitorExtension.swift',
        '$root/docs/ios-setup.md',
      ];
      final forbidden = <String>[
        'startModeSession(',
        'endModeSession(',
        'startManualModeSession(',
        'RestrictionModeUpsertCache',
        'getManualActiveModeId(',
        'setManualActiveModeId(',
        'loadManualActiveModeId(',
        'storeManualActiveModeId(',
        'manualActiveModeId',
        'legacyModeId',
      ];

      for (final path in paths) {
        final content = File(path).readAsStringSync();
        for (final needle in forbidden) {
          expect(content.contains(needle), isFalse, reason: 'Found forbidden legacy marker "$needle" in $path');
        }
      }
    });
  });
}
