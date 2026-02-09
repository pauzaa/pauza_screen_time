# Getting started

This guide shows the mode-based restriction flow on Android and iOS.

## 0) Install

```bash
flutter pub add pauza_screen_time
```

```dart
import 'package:pauza_screen_time/pauza_screen_time.dart';
```

## 1) Platform setup first

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
    .map((a) => AppIdentifier.android(a.packageId))
    .toList();

await restrictions.upsertMode(
  RestrictionMode(
    modeId: 'focus-mode',
    isEnabled: true,
    blockedAppIds: blocked,
  ),
);
await restrictions.setModesEnabled(true);
```

3. Start manual mode session:

```dart
await restrictions.startModeSession('focus-mode');
```

4. Inspect session:

```dart
final session = await restrictions.getRestrictionSession();
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
    .map((a) => AppIdentifier.ios(a.applicationToken))
    .toList();

await restrictions.upsertMode(
  RestrictionMode(
    modeId: 'focus-mode',
    isEnabled: true,
    blockedAppIds: blocked,
  ),
);
```

3. Optional schedule:

```dart
await restrictions.upsertMode(
  RestrictionMode(
    modeId: 'focus-mode',
    isEnabled: true,
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

## Next

- [restrict-apps.md](restrict-apps.md)
- [permissions.md](permissions.md)
- [installed-apps.md](installed-apps.md)
- [usage-stats.md](usage-stats.md)
- [troubleshooting.md](troubleshooting.md)
