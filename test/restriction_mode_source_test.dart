import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/features/restrict_apps/model/restriction_mode_source.dart';

void main() {
  group('RestrictionModeSource', () {
    test('fromWire parses all known values', () {
      expect(RestrictionModeSource.fromWire('none'), RestrictionModeSource.none);
      expect(RestrictionModeSource.fromWire('manual'), RestrictionModeSource.manual);
      expect(RestrictionModeSource.fromWire('schedule'), RestrictionModeSource.schedule);
    });

    test('fromWire throws ArgumentError on unknown value', () {
      expect(() => RestrictionModeSource.fromWire('unknown'), throwsArgumentError);
    });

    test('fromWire throws ArgumentError on empty string', () {
      expect(() => RestrictionModeSource.fromWire(''), throwsArgumentError);
    });

    test('wireValue round-trips for all values', () {
      for (final source in RestrictionModeSource.values) {
        expect(RestrictionModeSource.fromWire(source.wireValue), source);
      }
    });
  });
}
