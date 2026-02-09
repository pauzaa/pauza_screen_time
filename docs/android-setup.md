# Android setup

Android support uses:
- **UsageStatsManager** for usage statistics data
- **AccessibilityService** to detect when a restricted app is opened

This means your users must enable several system settings manually.

## Requirements

- Android 8.0+ (API 26+)

## 1) What the plugin already declares (manifest merging)

This plugin includes its own Android manifest at `android/src/main/AndroidManifest.xml` inside the plugin. Flutter/Gradle will **merge** it into your app when you add the dependency.

It declares:
- `android.permission.PACKAGE_USAGE_STATS` (Usage Access)
- `android.permission.QUERY_ALL_PACKAGES` (Android 11+ app enumeration)
- `android.permission.SCHEDULE_EXACT_ALARM` (Android 12+ exact alarm capability)
- Accessibility service `com.example.pauza_screen_time.app_restriction.AppMonitoringService`

### When you should edit your app manifest

Usually you **don’t need to** add anything to your app manifest if merging works correctly.

However, you *may* need to adjust your app if:
- you use a very restrictive manifest merger setup
- you want to add your own explanation UI / deep links
- Play Console policy requires changes related to `QUERY_ALL_PACKAGES`

## 2) Enable Usage Access (required for usage stats)

### Why this is needed

Android treats usage stats access as a special permission controlled in Settings. Without it, `UsageStatsManager.getUsageStats()` will return empty results or throw on the native side.

### How to request / open Settings

```dart
final permissions = PermissionManager();
await permissions.requestAndroidPermission(AndroidPermission.usageStats);
```

This call opens the Usage Access Settings screen. Re-check permission status after the user returns to the app.

### How to verify

1) Open **Settings** → **Security & privacy** (or similar) → **Usage access**
2) Find your app and ensure it is **Allowed**

## 3) Enable Accessibility service (required for blocking)

### Why this is needed

The plugin uses an `AccessibilityService` to detect foreground app changes. Without it, restrictions can be set but **nothing will trigger** when the user opens a blocked app.

### How to request / open Settings

```dart
final permissions = PermissionManager();
await permissions.requestAndroidPermission(AndroidPermission.accessibility);
```

This call opens the Accessibility Settings screen. Re-check permission status after the user returns to the app.

### How to verify

1) Open **Settings** → **Accessibility**
2) Find your app’s service and enable it
3) Re-open your app and try launching a restricted app — the shield should appear

## 4) Exact alarms for precise schedule timing (Android 12+)

### Why this is needed

Pause-end and schedule-boundary callbacks are most accurate when the app can schedule exact alarms.
Without exact-alarm capability on Android 12+ (API 31+), Android may delay callbacks.

### How to request / open Settings

```dart
final permissions = PermissionManager();
await permissions.requestAndroidPermission(AndroidPermission.exactAlarm);
```

### How to verify

1) Open **Settings** → **Apps** → **Special app access** → **Alarms & reminders** (paths vary by OEM)
2) Find your app and allow exact alarms

## 5) Notes about `QUERY_ALL_PACKAGES`

### What it’s for

`InstalledAppsManager.getAndroidInstalledApps()` enumerates installed apps. On Android 11+ this may require `android.permission.QUERY_ALL_PACKAGES`.

### Important Play policy note

Google Play restricts use of `QUERY_ALL_PACKAGES`. If you don’t qualify, you may need to remove this capability or limit queries via `<queries>` instead.

## 6) Pause auto-resume timing (AlarmManager)

### Why this matters

`pauseEnforcement(...)` stores pause state and schedules an AlarmManager callback at pause expiry.  
When that alarm fires, the plugin immediately re-evaluates the current foreground app and shows the shield if it is restricted (without waiting for the next accessibility event).

### Exact alarm behavior on Android 12+

The plugin manifest declares `android.permission.SCHEDULE_EXACT_ALARM` for best timing reliability.

On Android 12+ (API 31+), some devices/users may still restrict exact alarms via system settings.  
If exact alarms are not allowed, the plugin falls back to `setAndAllowWhileIdle`, and pause-end enforcement can be slightly delayed by the OS.

### How to verify

1) Pause for 1 minute while currently inside a restricted app  
2) Keep the app open  
3) At pause expiry, verify the shield appears automatically without app switching

## Troubleshooting

If blocking doesn’t work:
- Confirm **Accessibility** is enabled (step 3)
- Confirm you called `AppRestrictionManager.restrictApps()` with valid `AppIdentifier.android(packageId)` values

See [Troubleshooting](troubleshooting.md) for more.
