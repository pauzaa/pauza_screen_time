import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode_source.dart';

void main() {
  group('RestrictionModeSource', () {
    test('fromWire parses all known values', () {
      expect(RestrictionModeSource.fromWire('none'), RestrictionModeSource.none);
      expect(RestrictionModeSource.fromWire('manual'), RestrictionModeSource.manual);
      expect(RestrictionModeSource.fromWire('schedule'), RestrictionModeSource.schedule);
    });

    test('fromWire returns unknown for unrecognized value', () {
      expect(RestrictionModeSource.fromWire('future_value'), RestrictionModeSource.unknown);
    });

    test('fromWire returns unknown for empty string', () {
      expect(RestrictionModeSource.fromWire(''), RestrictionModeSource.unknown);
    });

    test('wireValue round-trips for all values', () {
      for (final source in RestrictionModeSource.values) {
        expect(RestrictionModeSource.fromWire(source.wireValue), source);
      }
    });
  });
}
