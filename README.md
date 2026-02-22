# pauza_screen_time

Flutter plugin for app usage monitoring, app restriction/blocking, and parental-control experiences.

Built for apps that need Screen Time authorization, app blocking, and usage insights across Android and iOS.

## Start here

- [Getting started](docs/getting-started.md) (end-to-end flow)
- [Android setup](docs/android-setup.md)
- [iOS setup](docs/ios-setup.md)
- [Permissions](docs/permissions.md)
- [Docs index](docs/README.md)

## What's included

- App restriction and blocking (Android + iOS 16+)
- App selection (Android enumeration, iOS picker tokens)
- Usage stats (Android data, iOS report UI)
- Permission helpers and typed errors

## Platform support

| Feature | Android | iOS |
|---|---:|---:|
| Permissions helpers | ✅ | ✅ (iOS 16+) |
| Installed apps | ✅ enumerate | ✅ picker tokens only |
| Restrict / block apps | ✅ (Accessibility + overlay) | ✅ (Screen Time, iOS 16+) |
| Restriction session snapshot | ✅ | ✅ |
| Pause enforcement API | ✅ | ✅ (reliable resume requires monitor extension) |
| Usage stats as data (`UsageStatsManager`) | ✅ | ❌ (throws `PauzaUnsupportedError`) |
| Usage stats as UI (`UsageReportView`) | ❌ | ✅ (iOS 16+, requires report extension) |

## Installation

```yaml
dependencies:
  pauza_screen_time:
    git:
      url: https://github.com/IsroilovA/pauza_screen_time
```

```dart
import 'package:pauza_screen_time/pauza_screen_time.dart';
```

## Quick start

Do platform setup first:
- Android: [docs/android-setup.md](docs/android-setup.md)
- iOS: [docs/ios-setup.md](docs/ios-setup.md)

For the full end-to-end flow, see [docs/getting-started.md](docs/getting-started.md).

```dart
final permissions = PermissionManager();
final installedApps = InstalledAppsManager();
final restrictions = AppRestrictionManager();

await permissions.requestAndroidPermission(AndroidPermission.accessibility);
await permissions.requestAndroidPermission(AndroidPermission.exactAlarm);

final androidApps = await installedApps.getAndroidInstalledApps(includeSystemApps: false);
final blocked = androidApps
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
await restrictions.startSession(
  RestrictionMode(
    modeId: 'focus-mode',
    blockedAppIds: blocked,
  ),
  duration: const Duration(minutes: 30),
);

// startSession(...) fails with INVALID_ARGUMENT if any session is already active.
// endSession() fails with INVALID_ARGUMENT when no session is active.
// endSession() clears both manual and schedule sessions.
// If a schedule session is ended inside an active interval, schedule reactivation is suppressed
// until that interval boundary, then normal schedule behavior resumes.

final session = await restrictions.getRestrictionSession();
// RestrictionState:
// session.activeMode / session.activeModeSource / session.isActiveNow
```

`getModesConfig()` returns only persisted scheduled modes that are needed for background enforcement.

## Common first blockers

- Permissions or Screen Time not granted yet: [docs/permissions.md](docs/permissions.md)
- Setup issues and error codes: [docs/troubleshooting.md](docs/troubleshooting.md), [docs/errors.md](docs/errors.md)

## Breaking API map (mode redesign)

- `restrictApps` / `restrictApp` / `unrestrictApp` / `clearAllRestrictions` -> `upsertMode` + `removeMode`
- `upsertScheduledMode` / `removeScheduledMode` / `setScheduledModesEnabled` / `getScheduledModesConfig` -> `upsertMode` / `removeMode` / `setModesEnabled` / `getModesConfig`
- `startRestrictionSession` / `endRestrictionSession` -> `startSession(mode, {duration})` / `endSession()`

## Session payload

`getRestrictionSession()` returns `RestrictionState`:
- `activeMode` (`RestrictionMode?`)
- `activeModeSource` (`none`, `manual`, `schedule`)
- `isActiveNow` (derived from `activeMode != null`)
- `isPausedNow` (derived from `pausedUntil != null`)

## Error handling

Plugin APIs throw typed `PauzaError` subclasses:

```dart
try {
  await AppRestrictionManager().upsertMode(
    const RestrictionMode(
      modeId: 'focus-mode',
      blockedAppIds: [AppIdentifier.android('com.instagram.android')],
    ),
  );
} on PauzaMissingPermissionError catch (error) {
  // error.details includes structured diagnostics.
}
```

Taxonomy codes: `UNSUPPORTED`, `MISSING_PERMISSION`, `PERMISSION_DENIED`, `SYSTEM_RESTRICTED`, `INVALID_ARGUMENT`, `INTERNAL_FAILURE`.

## Documentation

- [Docs index](docs/README.md)
- [Getting started](docs/getting-started.md)
- [Restrict / block apps](docs/restrict-apps.md)
- [Permissions](docs/permissions.md)
- [Installed apps](docs/installed-apps.md)
- [Usage stats](docs/usage-stats.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Error model](docs/errors.md)
