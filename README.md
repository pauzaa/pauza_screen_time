# pauza_screen_time

Flutter plugin for app usage monitoring, app restriction/blocking, and parental-control experiences.

## Platform support

| Feature | Android | iOS |
|---|---:|---:|
| Permissions helpers | ✅ | ✅ (iOS 16+) |
| Installed apps | ✅ enumerate | ✅ picker tokens only |
| Restrict / block apps | ✅ (Accessibility + overlay) | ✅ (Screen Time, iOS 16+) |
| Restriction session snapshot | ✅ | ✅ |
| Pause enforcement API | ✅ | ✅ (reliable resume requires monitor extension) |
| Usage stats as data (`UsageStatsManager`) | ✅ | ❌ (throws `UnsupportedError`) |
| Usage stats as UI (`UsageReportView`) | ❌ | ✅ (iOS 16+, requires report extension) |

## Installation

```bash
flutter pub add pauza_screen_time
```

```dart
import 'package:pauza_screen_time/pauza_screen_time.dart';
```

## Quick start

```dart
final permissions = PermissionManager();
final installedApps = InstalledAppsManager();
final restrictions = AppRestrictionManager();

await permissions.requestAndroidPermission(AndroidPermission.accessibility);
await permissions.requestAndroidPermission(AndroidPermission.exactAlarm);

final androidApps = await installedApps.getAndroidInstalledApps(includeSystemApps: false);
final blocked = androidApps
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
await restrictions.startManualModeSession(
  RestrictionMode(
    modeId: 'focus-mode',
    isEnabled: true,
    blockedAppIds: blocked,
  ),
);

final session = await restrictions.getRestrictionSession();
// session.activeModeId / session.activeModeSource
```

`getModesConfig()` returns only persisted scheduled modes that are needed for background enforcement.

## Breaking API map (mode redesign)

- `restrictApps` / `restrictApp` / `unrestrictApp` / `clearAllRestrictions` -> `upsertMode` + `removeMode`
- `upsertScheduledMode` / `removeScheduledMode` / `setScheduledModesEnabled` / `getScheduledModesConfig` -> `upsertMode` / `removeMode` / `setModesEnabled` / `getModesConfig`
- `startRestrictionSession` / `endRestrictionSession` -> `startModeSession(modeId)` / `endModeSession()`

## Session payload additions

`RestrictionSession` now includes:
- `activeModeId`
- `activeModeSource` (`none`, `manual`, `schedule`)

## Error handling

Plugin APIs throw typed `PauzaError` subclasses:

```dart
try {
  await AppRestrictionManager().upsertMode(
    const RestrictionMode(
      modeId: 'focus-mode',
      isEnabled: true,
      blockedAppIds: [AppIdentifier.android('com.instagram.android')],
    ),
  );
} on PauzaMissingPermissionError catch (error) {
  // error.details includes structured diagnostics.
}
```

Taxonomy codes: `UNSUPPORTED`, `MISSING_PERMISSION`, `PERMISSION_DENIED`, `SYSTEM_RESTRICTED`, `INVALID_ARGUMENT`, `INTERNAL_FAILURE`.

## Documentation

- [Getting started](docs/getting-started.md)
- [Restrict / block apps](docs/restrict-apps.md)
- [Permissions](docs/permissions.md)
- [Installed apps](docs/installed-apps.md)
- [Usage stats](docs/usage-stats.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Error model](docs/errors.md)
