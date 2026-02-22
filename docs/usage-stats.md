# Usage stats

This feature is platform-specific.

## Android: usage stats as data

### Why permissions matter

Android requires **Usage Access** (Settings permission) to read usage statistics.

See:
- [Android setup](android-setup.md) (Usage Access)
- [Permissions](permissions.md)

### Read usage stats for a time range

```dart
final usage = UsageStatsManager();

final now = DateTime.now();
final stats = await usage.getUsageStats(
  startDate: now.subtract(const Duration(days: 7)),
  endDate: now,
  includeIcons: true,
);
```

### Read usage stats for one app

```dart
final usage = UsageStatsManager();

final now = DateTime.now();
final app = await usage.getAppUsageStats(
  packageId: 'com.whatsapp',
  startDate: now.subtract(const Duration(days: 7)),
  endDate: now,
);
```

### Read raw usage events

```dart
final usage = UsageStatsManager();
final now = DateTime.now();

final events = await usage.getUsageEvents(
  startDate: now.subtract(const Duration(days: 2)),
  endDate: now,
  eventTypes: const [
    UsageEventType.activityResumed,
    UsageEventType.activityPaused,
  ],
);
```

`UsageEvent` includes:
- `timestamp`
- `packageName`
- `className` (nullable for system events)
- `eventType`

### Read aggregated device event stats (API 28+)

```dart
final usage = UsageStatsManager();
final now = DateTime.now();

final stats = await usage.getEventStats(
  startDate: now.subtract(const Duration(days: 7)),
  endDate: now,
  intervalType: UsageStatsInterval.daily,
);
```

This API requires Android 9+ (API 28). On lower Android versions, it throws a
typed `PauzaError` with taxonomy code `UNSUPPORTED`.

### Check app inactivity state

```dart
final usage = UsageStatsManager();

final inactive = await usage.isAppInactive(
  packageId: 'com.whatsapp',
);
```

### Read standby bucket (calling app, API 28+)

```dart
final usage = UsageStatsManager();
final bucket = await usage.getAppStandbyBucket();
```

Returns `AppStandbyBucket` (`active`, `workingSet`, `frequent`, `rare`,
`restricted`, `unknown`).

### Missing permission behavior

If Usage Access is not granted, Android usage stats calls fail with taxonomy code
`MISSING_PERMISSION`, which maps to `PauzaMissingPermissionError` in Dart.

Use the permissions API to request and re-check access before retrying:

```dart
final permissions = PermissionManager();
await permissions.requestAndroidPermission(AndroidPermission.usageStats);
```

### Typed error behavior

```dart
try {
  final usage = UsageStatsManager();
  final now = DateTime.now();
  await usage.getUsageStats(
    startDate: now.subtract(const Duration(days: 1)),
    endDate: now,
  );
} on PauzaMissingPermissionError {
  // Usage Access missing on Android.
} on PauzaUnsupportedError {
  // Called on unsupported platform/API level.
}
```

### Android schema semantics

Each `UsageStats` item includes:

- `totalDuration` (`totalDurationMs`): total foreground time for the app.
- `totalLaunchCount`: number of `ACTIVITY_RESUMED` events in the query window.
- `bucketStart` (`bucketStartMs`): Android usage bucket start (`UsageStats.firstTimeStamp`).
- `bucketEnd` (`bucketEndMs`): Android usage bucket end (`UsageStats.lastTimeStamp`).
- `lastTimeUsed` (`lastTimeUsedMs`): last foreground usage time (`UsageStats.lastTimeUsed`).
- `lastTimeVisible` (`lastTimeVisibleMs`): last visible time on Android Q+ (`UsageStats.lastTimeVisible`).

Timestamps are sent as epoch milliseconds and deserialized to local `DateTime` values in Dart.
They represent instants in time; local rendering depends on the device time zone.

Notes:

- `bucketStart` / `bucketEnd` are system bucket boundaries, not "first use" or "last use" in your query.
- Some fields may be `null` depending on Android version, OEM behavior, or data availability.

## iOS: usage stats as UI (`UsageReportView`)

### Important limitation

On iOS, Apple does **not** let you read Screen Time usage stats as Dart data.
The plugin exposes a native UI report you embed in Flutter:

- Widget: `UsageReportView` / `IOSUsageReportView`
- Native view type: `pauza_screen_time/usage_report`

All `UsageStatsManager` methods are Android-only and throw
`PauzaUnsupportedError` on iOS.

### Setup requirement

You must create a **Device Activity Report extension** target in the host iOS app.

See [iOS setup](ios-setup.md).
Template file: `docs/templates/PauzaDeviceActivityReportExtension.swift`.

### Example: embed a report

```dart
IOSUsageReportView(
  reportContext: 'daily',
  segment: IOSUsageReportSegment.daily,
  startDate: DateTime.now().subtract(const Duration(days: 7)),
  endDate: DateTime.now(),
  fallback: SizedBox.shrink(),
)
```

### Choosing `reportContext`

The plugin passes your string directly to:

```swift
DeviceActivityReport.Context(reportContextId)
```

Your report extension must support the same context identifiers.
The provided template includes context `daily`.

## Next

- [Docs index](README.md)
- [Permissions](permissions.md)
- [iOS setup](ios-setup.md)
- [Troubleshooting](troubleshooting.md)
