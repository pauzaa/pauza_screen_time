import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/core.dart';
import 'package:pauza_screen_time/src/features/installed_apps/model/app_info.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ---------------------------------------------------------------------------
  // AndroidAppInfo
  // ---------------------------------------------------------------------------

  group('AndroidAppInfo.fromMap', () {
    test('parses a valid map', () {
      final map = {
        'platform': 'android',
        'packageId': 'com.example.app',
        'name': 'Example App',
        'icon': null,
        'category': 'Social',
        'isSystemApp': true,
      };
      final info = AndroidAppInfo.fromMap(map);
      expect(info.packageId.raw, 'com.example.app');
      expect(info.name, 'Example App');
      expect(info.category, 'Social');
      expect(info.isSystemApp, isTrue);
      expect(info.icon, isNull);
    });

    test('defaults isSystemApp to false when absent', () {
      final map = {'platform': 'android', 'packageId': 'com.example.app', 'name': 'Example App'};
      final info = AndroidAppInfo.fromMap(map);
      expect(info.isSystemApp, isFalse);
    });

    test('throws PauzaInternalFailureError when packageId is missing', () {
      final map = {'platform': 'android', 'name': 'App'};
      expect(() => AndroidAppInfo.fromMap(map), throwsA(isA<PauzaInternalFailureError>()));
    });

    test('throws PauzaInternalFailureError when name is missing', () {
      final map = {'platform': 'android', 'packageId': 'com.x'};
      expect(() => AndroidAppInfo.fromMap(map), throwsA(isA<PauzaInternalFailureError>()));
    });

    test('throws PauzaInternalFailureError when packageId has wrong type', () {
      final map = {'platform': 'android', 'packageId': 42, 'name': 'App'};
      expect(() => AndroidAppInfo.fromMap(map), throwsA(isA<PauzaInternalFailureError>()));
    });
  });

  group('AndroidAppInfo.toMap round-trip', () {
    test('round-trips through toMap -> fromMap', () {
      const original = AndroidAppInfo(
        packageId: AppIdentifier.android('com.example.app'),
        name: 'Example App',
        category: 'Games',
      );
      final map = original.toMap();
      final restored = AndroidAppInfo.fromMap(map);
      expect(restored.packageId, original.packageId);
      expect(restored.name, original.name);
      expect(restored.category, original.category);
      expect(restored.isSystemApp, original.isSystemApp);
    });
  });

  // ---------------------------------------------------------------------------
  // IOSAppInfo
  // ---------------------------------------------------------------------------

  group('IOSAppInfo.fromMap', () {
    test('parses a valid map', () {
      final map = {'platform': 'ios', 'applicationToken': 'abc123token'};
      final info = IOSAppInfo.fromMap(map);
      expect(info.applicationToken.raw, 'abc123token');
    });

    test('throws PauzaInternalFailureError when applicationToken is missing', () {
      final map = {'platform': 'ios'};
      expect(() => IOSAppInfo.fromMap(map), throwsA(isA<PauzaInternalFailureError>()));
    });

    test('throws PauzaInternalFailureError when applicationToken has wrong type', () {
      final map = {'platform': 'ios', 'applicationToken': 123};
      expect(() => IOSAppInfo.fromMap(map), throwsA(isA<PauzaInternalFailureError>()));
    });
  });

  group('IOSAppInfo.toMap round-trip', () {
    test('round-trips through toMap -> fromMap', () {
      const original = IOSAppInfo(applicationToken: AppIdentifier.ios('myToken'));
      final map = original.toMap();
      final restored = IOSAppInfo.fromMap(map);
      expect(restored.applicationToken, original.applicationToken);
    });
  });

  // ---------------------------------------------------------------------------
  // AppInfo.fromMap (sealed dispatch)
  // ---------------------------------------------------------------------------

  group('AppInfo.fromMap', () {
    test('dispatches to AndroidAppInfo for platform=android', () {
      final map = {'platform': 'android', 'packageId': 'com.x', 'name': 'X'};
      expect(AppInfo.fromMap(map), isA<AndroidAppInfo>());
    });

    test('dispatches to IOSAppInfo for platform=ios', () {
      final map = {'platform': 'ios', 'applicationToken': 'tok'};
      expect(AppInfo.fromMap(map), isA<IOSAppInfo>());
    });

    test('throws PauzaInternalFailureError for unknown platform', () {
      final map = {'platform': 'windows', 'packageId': 'x'};
      expect(() => AppInfo.fromMap(map), throwsA(isA<PauzaInternalFailureError>()));
    });

    test('throws PauzaInternalFailureError when platform is null', () {
      final map = <String, dynamic>{'packageId': 'x'};
      expect(() => AppInfo.fromMap(map), throwsA(isA<PauzaInternalFailureError>()));
    });

    test('throws PauzaInternalFailureError when platform is wrong type', () {
      final map = {'platform': 42, 'packageId': 'x'};
      expect(() => AppInfo.fromMap(map), throwsA(isA<PauzaInternalFailureError>()));
    });
  });

  // ---------------------------------------------------------------------------
  // PlatformException inside _requireString should encode field diagnostics
  // ---------------------------------------------------------------------------

  group('error diagnostics', () {
    test('error from missing packageId includes field name in message', () {
      final map = {'platform': 'android', 'name': 'App'};
      try {
        AndroidAppInfo.fromMap(map);
        fail('expected exception');
      } on PauzaInternalFailureError catch (e) {
        // PauzaInternalFailureError inherits from PlatformException;
        // verify the message mentions the field.
        expect(e.message, contains('packageId'));
      }
    });
  });
}
