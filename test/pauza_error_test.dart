import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/core/pauza_error.dart';

void main() {
  group('PauzaError.fromPlatformException', () {
    test('maps stable taxonomy codes to typed subclasses', () {
      expect(PauzaError.fromPlatformException(PlatformException(code: 'UNSUPPORTED')), isA<PauzaUnsupportedError>());
      expect(
        PauzaError.fromPlatformException(PlatformException(code: 'MISSING_PERMISSION')),
        isA<PauzaMissingPermissionError>(),
      );
      expect(
        PauzaError.fromPlatformException(PlatformException(code: 'PERMISSION_DENIED')),
        isA<PauzaPermissionDeniedError>(),
      );
      expect(
        PauzaError.fromPlatformException(PlatformException(code: 'SYSTEM_RESTRICTED')),
        isA<PauzaSystemRestrictedError>(),
      );
      expect(
        PauzaError.fromPlatformException(PlatformException(code: 'INVALID_ARGUMENT')),
        isA<PauzaInvalidArgumentError>(),
      );
    });

    test('maps unknown codes to internal failure subtype', () {
      final error = PauzaError.fromPlatformException(PlatformException(code: 'SOME_LEGACY_CODE'));
      expect(error, isA<PauzaInternalFailureError>());
      expect(error.code, 'INTERNAL_FAILURE');
      expect(error.rawCode, 'SOME_LEGACY_CODE');
    });
  });
}
