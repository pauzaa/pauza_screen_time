import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:pauza_screen_time/src/core/method_channel_names.dart';
import 'package:pauza_screen_time/src/core/method_names.dart';

/// Core method-channel calls that are not tied to a feature module.
class CoreMethodChannel {
  @visibleForTesting
  final MethodChannel channel;

  CoreMethodChannel({MethodChannel? channel}) : channel = channel ?? const MethodChannel(MethodChannelNames.core);

  /// Returns the current platform version (for testing/debugging).
  Future<String?> getPlatformVersion() {
    return channel.invokeMethod<String>(MethodNames.getPlatformVersion);
  }
}
