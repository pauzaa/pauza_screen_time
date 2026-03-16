import 'dart:io' show Platform;

import 'package:pauza_screen_time/src/core/pauza_error.dart';

/// Asserts the current platform is Android, throwing [PauzaUnsupportedError]
/// if not.
void assertAndroid(String methodName) {
  if (!Platform.isAndroid) {
    throw PauzaUnsupportedError(
      message: '$methodName is only supported on Android. '
          'On iOS, use the DeviceActivityReport platform view.',
      rawCode: 'UNSUPPORTED',
    );
  }
}

/// Asserts the current platform is iOS, throwing [PauzaUnsupportedError]
/// if not.
void assertIOS(String methodName) {
  if (!Platform.isIOS) {
    throw PauzaUnsupportedError(
      message: '$methodName is only available on iOS',
      rawCode: 'UNSUPPORTED',
    );
  }
}
