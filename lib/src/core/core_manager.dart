import 'package:pauza_screen_time/src/core/core_method_channel.dart';

/// Core plugin APIs that are safe/cross-platform and not feature-specific.
class CoreManager {
  final CoreMethodChannel _channel;

  CoreManager({CoreMethodChannel? channel}) : _channel = channel ?? CoreMethodChannel();

  /// Returns the current platform version (for testing/debugging).
  Future<String?> getPlatformVersion() => _channel.getPlatformVersion();
}
