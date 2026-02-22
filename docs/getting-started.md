# Getting started

This guide shows the mode-based restriction flow on Android and iOS.

## When to use this guide

Use this guide for a full end-to-end restriction flow. If you only need a
specific area, jump to:
- [Permissions](permissions.md)
- [Usage stats](usage-stats.md)
- [Restrict / block apps](restrict-apps.md)

## 0) Install

```yaml
dependencies:
  pauza_screen_time:
    git:
      url: https://github.com/IsroilovA/pauza_screen_time
```

```dart
import 'package:pauza_screen_time/pauza_screen_time.dart';
```

## 1) Platform setup first

Complete platform setup before calling restriction APIs; they will fail fast if
prerequisites are missing.

- Android: [android-setup.md](android-setup.md)
- iOS: [ios-setup.md](ios-setup.md)

## 2) Instantiate managers

```dart
final permissions = PermissionManager();
final installedApps = InstalledAppsManager();
final restrictions = AppRestrictionManager();
final usage = UsageStatsManager();
```

## 3) Android flow

1. Request permissions:

```dart
await permissions.requestAndroidPermission(AndroidPermission.usageStats);
await permissions.requestAndroidPermission(AndroidPermission.accessibility);
await permissions.requestAndroidPermission(AndroidPermission.exactAlarm);
```

2. Build blocked ids and upsert mode:

```dart
final apps = await installedApps.getAndroidInstalledApps(includeSystemApps: false);
final blocked = apps
    .take(3)
    .map((a) => a.packageId)
    .toList();

await restrictions.upsertMode(
  RestrictionMode(
    modeId: 'focus-mode',
    blockedAppIds: blocked,
  ),
);
await restrictions.setModesEnabled(true);
```

3. Start session:

```dart
await restrictions.startSession(
  RestrictionMode(
    modeId: 'focus-mode',
    blockedAppIds: blocked,
  ),
  duration: const Duration(minutes: 30), // optional
);
```

`startSession(...)` rejects with `INVALID_ARGUMENT` if any session is already active.
Call `endSession()` first, then start a new one.

4. Inspect session:

```dart
final session = await restrictions.getRestrictionSession();
final activeMode = session.activeMode; // RestrictionMode? (null when inactive)
// session is RestrictionState
```

## 4) iOS flow

1. Request Screen Time authorization:

```dart
final granted = await permissions.requestIOSPermission(IOSPermission.familyControls);
if (!granted) return;
```

2. Pick tokens and upsert mode:

```dart
final picked = await installedApps.selectIOSApps();
final blocked = picked
    .map((a) => a.applicationToken)
    .toList();

await restrictions.upsertMode(
  RestrictionMode(
    modeId: 'focus-mode',
    blockedAppIds: blocked,
  ),
);
```

3. Optional schedule:

```dart
await restrictions.upsertMode(
  RestrictionMode(
    modeId: 'focus-mode',
    schedule: const RestrictionSchedule(
      daysOfWeekIso: {1, 2, 3, 4, 5},
      startMinutes: 9 * 60,
      endMinutes: 12 * 60,
    ),
    blockedAppIds: blocked,
  ),
);
await restrictions.setModesEnabled(true);
```

4. Pause and resume:

```dart
await restrictions.pauseEnforcement(const Duration(minutes: 5));
await restrictions.resumeEnforcement();
```

Pause duration must be strictly less than 24 hours on both Android and iOS.
Manual `startSession(..., duration: ...)` follows the same `< 24h` upper bound.

## Next

- [Docs index](README.md)
- [restrict-apps.md](restrict-apps.md)
- [permissions.md](permissions.md)
- [installed-apps.md](installed-apps.md)
- [usage-stats.md](usage-stats.md)
- [troubleshooting.md](troubleshooting.md)
