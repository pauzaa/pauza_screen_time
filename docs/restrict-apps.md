# Restrict / block apps

This guide covers the app restriction API (`AppRestrictionManager`) and how to configure the blocking “shield”.

## How restrictions work

### Android

- You provide **package names** (example: `com.whatsapp`).
- The plugin uses an AccessibilityService to detect when the restricted app is opened.
- The plugin shows an overlay “shield” on top of the app.
- During `pauseEnforcement(...)`, blocked apps are temporarily allowed until pause expiry.

### iOS

- You provide **base64 `ApplicationToken` strings** (opaque).
- Tokens come from the iOS picker: `InstalledAppsManager.selectIOSApps()`.
- iOS enforces restrictions via `ManagedSettingsStore.shield.applications`.
- During `pauseEnforcement(...)`, the plugin clears managed shields and restores them after pause state ends.
- Reliable timed auto-resume while app is not running requires a host **Device Activity Monitor Extension**.

## 1) Configure the shield UI

Call `configureShield()` before restricting apps.

```dart
final restrictions = AppRestrictionManager();

await restrictions.configureShield(const ShieldConfiguration(
  title: 'Restricted',
  subtitle: 'Ask a parent for more time.',
  // iOS-only, recommended when using extensions:
  appGroupId: 'group.com.yourcompany.yourapp',
  // Optional:
  backgroundBlurStyle: BackgroundBlurStyle.regular,
  primaryButtonLabel: 'OK',
));
```

### Why App Groups matter on iOS

On iOS, `configureShield()` stores the configuration in **App Group UserDefaults** under the key `shieldConfiguration`.

If the App Group is not configured correctly, iOS returns `INTERNAL_FAILURE` with diagnostic details.

See [iOS setup](ios-setup.md).

## 2) Restrict apps (Android)

```dart
final restrictions = AppRestrictionManager();

await restrictions.restrictApps([
  AppIdentifier.android('com.whatsapp'),
  AppIdentifier.android('com.instagram.android'),
]);
```

To add/remove one at a time:

```dart
await restrictions.restrictApp(AppIdentifier.android('com.whatsapp'));
await restrictions.unrestrictApp(AppIdentifier.android('com.whatsapp'));
```

## 3) Restrict apps (iOS)

### Step A: request authorization

```dart
final permissions = PermissionManager();
await permissions.requestIOSPermission(IOSPermission.familyControls);
```

### Step B: pick apps (tokens)

```dart
final installedApps = InstalledAppsManager();
final picked = await installedApps.selectIOSApps();

final identifiers = picked
    .map((a) => AppIdentifier.ios(a.applicationToken))
    .toList();
```

### Step C: apply restrictions using tokens

```dart
final restrictions = AppRestrictionManager();
await restrictions.restrictApps(identifiers);
```

Typed error handling:

```dart
try {
  await restrictions.restrictApps(identifiers);
} on PauzaError catch (error) {
  // Handle `MISSING_PERMISSION` / `PERMISSION_DENIED` / etc.
}
```

## 4) Query current restrictions

```dart
final restrictions = AppRestrictionManager();

final current = await restrictions.getRestrictedApps();
final isBlocked = await restrictions.isAppRestricted(current.first);
```

## 5) Restriction session snapshot

```dart
final restrictions = AppRestrictionManager();

final isActiveNow = await restrictions.isRestrictionSessionActiveNow();
final isConfigured = await restrictions.isRestrictionSessionConfigured();
final session = await restrictions.getRestrictionSession();
```

`RestrictionSession` now includes:
- `isActiveNow`: restrictions are currently enforcing (configured, not paused, and all prerequisites are satisfied)
- `isPausedNow`: pause is currently active
- `isManuallyEnabled`: manual session toggle state
- `isScheduleEnabled`: schedule toggle state
- `isInScheduleNow`: current local time is inside a configured schedule window
- `pausedUntil`: pause expiration timestamp, if paused
- `restrictedApps`: currently configured restricted identifiers

## 6) Pause and resume enforcement

```dart
final restrictions = AppRestrictionManager();

await restrictions.pauseEnforcement(const Duration(minutes: 5));
await restrictions.resumeEnforcement();
```

Behavior:
- Calling pause while already paused returns `INVALID_ARGUMENT`.
- iOS requires pause duration `< 24h`; longer durations return `INVALID_ARGUMENT`.
- While paused, `isRestrictionSessionActiveNow()` returns `false`.
- `isRestrictionSessionConfigured()` can still return `true` during pause.
- Android resumes enforcement automatically after pause expiry and re-checks the current foreground app immediately.
- iOS schedules a Device Activity pause monitor and resumes after expiry through the host monitor extension.
- If iOS cannot schedule the monitor interval, pause fails with `INTERNAL_FAILURE`.

## 7) Manual session controls

```dart
final restrictions = AppRestrictionManager();

await restrictions.startRestrictionSession();
await restrictions.endRestrictionSession();
```

Behavior:
- Manual session controls whether restrictions are active outside scheduled windows.
- If a manual session is active, schedule boundaries do not force-stop it.

## 8) One mode → one schedule APIs

If your host app stores Modes/Schedules in SQLite, save there first, then call plugin APIs to sync shared native config:

```dart
await restrictions.upsertScheduledMode(
  RestrictionScheduledMode(
    modeId: 'focus-mode',
    isEnabled: true,
    schedule: const RestrictionSchedule(
      daysOfWeekIso: {1, 2, 3, 4, 5},
      startMinutes: 9 * 60,
      endMinutes: 12 * 60,
    ),
    blockedAppIds: [
      AppIdentifier.android('com.instagram.android'),
    ],
  ),
);

await restrictions.setScheduledModesEnabled(true);
```

Notes:
- Each mode can have only one schedule in this API.
- Schedules across modes must not overlap.
- If a manual session is enabled (`startRestrictionSession()`), schedule-based mode switching is ignored until manual mode ends.

## 9) Fail-safe enforcement errors

When you apply restrictions while prerequisites are missing, the plugin now fails safely with stable error codes:

- Android, Accessibility disabled:
  - `MISSING_PERMISSION`
  - `details.missing` includes `android.accessibility`
- iOS, Screen Time not requested yet:
  - `MISSING_PERMISSION`
  - `details.missing` includes `ios.familyControls`
- iOS, Screen Time denied:
  - `PERMISSION_DENIED`

Use `PauzaError.fromPlatformException(...)` to map these to typed Dart error categories.

## Verification checklist

- **Android**:
  - Usage Access enabled (recommended for usage stats)
  - Accessibility enabled (required for blocking triggers)
  - Restrict an app you can easily launch to test
  - Pause for 1 minute and confirm blocked app becomes usable, then re-blocks after expiry
- **iOS**:
  - iOS 16+
  - Screen Time authorization approved
  - Tokens come from `selectIOSApps()` (don’t invent them)
  - For reliable pause auto-resume (including when the app is backgrounded/terminated), Device Activity Monitor extension is configured

## Next

- [Installed apps](installed-apps.md)
- [Permissions](permissions.md)
- [Troubleshooting](troubleshooting.md)
