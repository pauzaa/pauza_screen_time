import 'package:flutter_test/flutter_test.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/app_standby_bucket.dart';
import 'package:pauza_screen_time/src/features/usage_stats/model/usage_stats_interval.dart';

void main() {
  group('UsageStatsInterval', () {
    test('fromRawValue returns correct enum for all known values', () {
      expect(UsageStatsInterval.fromRawValue(0), UsageStatsInterval.best);
      expect(UsageStatsInterval.fromRawValue(1), UsageStatsInterval.daily);
      expect(UsageStatsInterval.fromRawValue(2), UsageStatsInterval.weekly);
      expect(UsageStatsInterval.fromRawValue(3), UsageStatsInterval.monthly);
      expect(UsageStatsInterval.fromRawValue(4), UsageStatsInterval.yearly);
    });

    test('fromRawValue falls back to best for unknown values', () {
      expect(UsageStatsInterval.fromRawValue(99), UsageStatsInterval.best);
      expect(UsageStatsInterval.fromRawValue(-1), UsageStatsInterval.best);
    });

    test('rawValue round-trips correctly for all values', () {
      for (final interval in UsageStatsInterval.values) {
        expect(UsageStatsInterval.fromRawValue(interval.rawValue), interval);
      }
    });
  });

  group('AppStandbyBucket', () {
    test('fromRawValue returns correct enum for all known values', () {
      expect(AppStandbyBucket.fromRawValue(10), AppStandbyBucket.active);
      expect(AppStandbyBucket.fromRawValue(20), AppStandbyBucket.workingSet);
      expect(AppStandbyBucket.fromRawValue(30), AppStandbyBucket.frequent);
      expect(AppStandbyBucket.fromRawValue(40), AppStandbyBucket.rare);
      expect(AppStandbyBucket.fromRawValue(45), AppStandbyBucket.restricted);
    });

    test('fromRawValue falls back to unknown for unrecognised values', () {
      expect(AppStandbyBucket.fromRawValue(999), AppStandbyBucket.unknown);
      expect(AppStandbyBucket.fromRawValue(0), AppStandbyBucket.unknown);
    });

    test('rawValue round-trips correctly for non-unknown values', () {
      for (final bucket in AppStandbyBucket.values) {
        if (bucket == AppStandbyBucket.unknown) continue;
        expect(AppStandbyBucket.fromRawValue(bucket.rawValue), bucket);
      }
    });
  });
}
