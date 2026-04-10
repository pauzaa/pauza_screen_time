# pauza_screen_time

A Flutter plugin for app restriction, usage monitoring, and parental-control experiences on Android and iOS. It is the native engine behind the [Pauza](https://pauza.dev) digital wellbeing app.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Platform Setup](#platform-setup)
  - [Android](#android)
  - [iOS](#ios)
- [Quick Start](#quick-start)
- [API Reference](#api-reference)
- [Key Types](#key-types)
- [Error Handling](#error-handling)
- [Running the Example App](#running-the-example-app)
- [Running Tests](#running-tests)
- [Breaking API Changes](#breaking-api-changes)
- [Platform Support](#platform-support)

---

## Features

| Feature | Android | iOS |
|---------|---------|-----|
| List installed apps | ✅ | — |
| Pick apps to restrict | — | ✅ (FamilyActivityPicker) |
| Block / restrict apps | ✅ (Accessibility Service + LockActivity) | ✅ (Screen Time / ManagedSettings) |
| Timed restriction sessions | ✅ | ✅ |
| Weekly restriction schedules | ✅ | ✅ |
| Pause enforcement | ✅ | ✅ |
| Usage statistics per app | ✅ | — |
| Raw usage event stream | ✅ | — |
| Usage report UI | — | ✅ (DeviceActivityReport) |
| Custom blocking shield | ✅ | ✅ |
| Permission helpers | ✅ | ✅ |

---

## Prerequisites

### Common (all platforms)

| Tool | Minimum version | How to install |
|------|----------------|----------------|
| Flutter SDK | 3.3.0 | [flutter.dev/docs/get-started/install](https://flutter.dev/docs/get-started/install) |
| Dart SDK | 3.9.2 | Bundled with Flutter — no separate install needed |

Verify your Flutter installation:

```bash
flutter doctor
```

### Android

| Requirement | Notes |
|-------------|-------|
| Android Studio **or** VS Code with Flutter/Dart extensions | For building, running, and debugging |
| Android SDK | API level 26 (Android 8.0 Oreo) or higher |
| Physical Android device or emulator (API 26+) | The Accessibility Service does **not** function reliably on all emulators; a physical device is strongly recommended |
| Java 17 | Bundled with recent Android Studio; verify with `java -version` |

Install Android Studio: [developer.android.com/studio](https://developer.android.com/studio)

### iOS

| Requirement | Notes |
|-------------|-------|
| macOS | iOS builds require macOS |
| Xcode 15+ | Download from the Mac App Store |
| iOS 16.0+ physical device | The Simulator does **not** support Family Controls; a real device is required |
| Apple Developer account | Needed to enable App Groups and Family Controls entitlements |
| CocoaPods | `sudo gem install cocoapods` (or via Homebrew: `brew install cocoapods`) |

After installing Xcode, accept the license and install command-line tools:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
```

---

## Installation

Add the plugin to your `pubspec.yaml`:

```yaml
dependencies:
  pauza_screen_time:
    git:
      url: https://github.com/pauzaa/pauza_screen_time
```

Fetch dependencies:

```bash
flutter pub get
```

Import the package wherever needed:

```dart
import 'package:pauza_screen_time/pauza_screen_time.dart';
```

---

## Platform Setup

### Android

#### 1. Add manifest permissions

In your app's `android/app/src/main/AndroidManifest.xml`, inside the `<manifest>` element:

```xml
<uses-permission android:name="android.permission.PACKAGE_USAGE_STATS"
    tools:ignore="ProtectedPermissions" />
<uses-permission android:name="android.permission.QUERY_ALL_PACKAGES"
    tools:ignore="QueryAllPackagesPermission" />
<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM" />
<uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />
```

#### 2. Runtime permission guidance

The following permissions **cannot** be granted via a standard runtime dialog — the user must enable them manually in system Settings. Use `PermissionManager` to detect what is missing and open the correct screen:

| Permission | Where to enable |
|-----------|-----------------|
| Usage Access | Settings → Apps → Special app access → Usage access |
| Accessibility | Settings → Accessibility → [Your App] → Enable |
| Exact alarms (Android 12+) | Settings → Apps → [Your App] → Alarms & reminders |

```dart
final missing = await permissionManager.getMissingAndroidPermissions();
if (missing.isNotEmpty) {
  await permissionManager.openAndroidPermissionSettings(missing.first);
}
```

---

### iOS

#### 1. Enable App Groups

In Xcode, select your app target → **Signing & Capabilities** → **+ Capability** → **App Groups**. Create a group ID such as `group.com.yourcompany.yourapp`.

Set the same ID in `ios/Runner/Info.plist`:

```xml
<key>AppGroupIdentifier</key>
<string>group.com.yourcompany.yourapp</string>
```

#### 2. Enable Family Controls

Add the **Family Controls** capability to your app target (requires enrollment in the Apple Developer Program).

Request authorization at runtime before calling any restriction or app-selection API:

```dart
await permissionManager.requestIOSPermission(IOSPermission.familyControls);
```

#### 3. (Recommended) Device Activity Monitor extension

Required for reliable pause auto-resume while the app is in the background. In Xcode, add a new **Device Activity Monitor** extension target.

#### 4. (Optional) Shield Configuration extension

Lets you fully customize the blocking shield UI shown to the user. Add a **Shield Configuration** extension target in Xcode.

#### 5. (Optional) Device Activity Report extension

Required only if you use the `UsageReportView` widget. Add a **Device Activity Report** extension target in Xcode.

---

## Quick Start

```dart
import 'package:pauza_screen_time/pauza_screen_time.dart';

final permissions = PermissionManager();
final apps = InstalledAppsManager();
final restrictions = AppRestrictionManager();

// 1. Ensure required permissions are granted (Android example)
final missing = await permissions.getMissingAndroidPermissions();
for (final p in missing) {
  await permissions.openAndroidPermissionSettings(p);
}

// 2. Enumerate installed apps and choose which ones to block
final installed = await apps.getAndroidInstalledApps(includeSystemApps: false);
final toBlock = installed.take(3).map((a) => a.packageId).toList();

// 3. Persist a restriction mode
await restrictions.upsertMode(
  RestrictionMode(
    modeId: 'focus-mode',
    blockedAppIds: toBlock,
  ),
);

// 4. Start a 30-minute focus session
await restrictions.startSession(
  RestrictionMode(modeId: 'focus-mode', blockedAppIds: toBlock),
  duration: const Duration(minutes: 30),
);

// 5. Check active session state
final state = await restrictions.getRestrictionSession();
print(state.isActiveNow);    // true
print(state.activeModeSource); // RestrictionModeSource.manual

// 6. End early if needed
await restrictions.endSession();
```

iOS quick start (uses FamilyActivityPicker instead of enumeration):

```dart
// Pick apps interactively
final selected = await apps.selectIOSApps();

await restrictions.upsertMode(
  RestrictionMode(
    modeId: 'focus-mode',
    blockedAppIds: selected.map((a) => a.applicationToken).toList(),
  ),
);
await restrictions.startSession(
  RestrictionMode(
    modeId: 'focus-mode',
    blockedAppIds: selected.map((a) => a.applicationToken).toList(),
  ),
  duration: const Duration(minutes: 25),
);
```

---

## API Reference

### PermissionManager

| Method | Platforms | Description |
|--------|-----------|-------------|
| `checkAndroidPermission(AndroidPermission)` | Android | Returns the current `PermissionStatus` for a single permission |
| `requestAndroidPermission(AndroidPermission)` | Android | Opens the appropriate system Settings screen |
| `openAndroidPermissionSettings(AndroidPermission)` | Android | Same as above — explicit alias |
| `checkAndroidPermissions(List<AndroidPermission>)` | Android | Batch status check |
| `getMissingAndroidPermissions([subset])` | Android | Returns only the permissions that are not yet granted |
| `checkIOSPermission(IOSPermission)` | iOS | Returns the current `PermissionStatus` |
| `requestIOSPermission(IOSPermission)` | iOS | Presents the system authorization dialog |
| `checkIOSPermissions(List<IOSPermission>)` | iOS | Batch status check |
| `getMissingIOSPermissions([subset])` | iOS | Returns only the permissions that are not yet granted |

**`AndroidPermission` values:** `usageStats`, `accessibility`, `exactAlarm`, `queryAllPackages`

**`IOSPermission` values:** `familyControls`, `screenTime`

---

### InstalledAppsManager

| Method | Platforms | Description |
|--------|-----------|-------------|
| `getAndroidInstalledApps({includeSystemApps, includeIcons, cancelToken, timeout})` | Android | Returns all installed apps |
| `getAndroidAppInfo(AppIdentifier, {includeIcons, cancelToken, timeout})` | Android | Metadata for a single package |
| `isAndroidAppInstalled(AppIdentifier)` | Android | `true` if the package is installed |
| `selectIOSApps({preSelectedApps})` | iOS | Opens FamilyActivityPicker; returns `List<IOSAppInfo>` |

---

### AppRestrictionManager

| Method | Description |
|--------|-------------|
| `upsertMode(RestrictionMode)` | Create or update a restriction mode |
| `removeMode(String modeId)` | Delete a mode by ID |
| `replaceAllModes(List<RestrictionMode>)` | Atomically replace all persisted modes |
| `configureShield(ShieldConfiguration)` | Customize the blocking shield appearance |
| `getModesConfig()` | Load persisted scheduled modes |
| `setScheduleEnforcementEnabled(bool)` | Toggle automatic schedule enforcement on/off |
| `startSession(RestrictionMode, {Duration?})` | Begin enforcement; auto-ends after duration if provided |
| `endSession({Duration?, RestrictionLifecycleReason?})` | Stop enforcement immediately or after a delay |
| `pauseEnforcement(Duration)` | Temporarily lift restrictions for the given duration |
| `resumeEnforcement()` | Re-apply restrictions before the pause expires |
| `isRestrictionSessionActiveNow()` | `true` if a session is currently active |
| `getRestrictionSession()` | Returns a `RestrictionState` snapshot |
| `getPendingLifecycleEvents({int limit})` | Fetch durable session lifecycle events |
| `ackLifecycleEvents({required String throughEventId})` | Mark events as consumed up to the given ID |

**Session rules to be aware of:**

- `startSession()` throws `INVALID_ARGUMENT` if a session is already active.
- `endSession()` throws `INVALID_ARGUMENT` when no session is active.
- `endSession(duration: ...)` accepts only durations `> 0` and `< 24 h`.
- `pauseEnforcement()` requires an active, non-paused session.
- `resumeEnforcement()` requires an active, currently-paused session.
- When a scheduled session is ended inside an active schedule interval, reactivation is suppressed until the interval boundary.

---

### UsageStatsManager (Android only)

| Method | Description |
|--------|-------------|
| `getUsageStats({startDate, endDate, includeIcons, cancelToken, timeout})` | Per-app foreground time for a date range |
| `getAppUsageStats({packageId, startDate, endDate, ...})` | Usage stats for a single package |
| `getUsageEvents({startDate, endDate, eventTypes, ...})` | Raw timestamped app events |
| `getEventStats({startDate, endDate, intervalType, ...})` | Aggregated device events (screen on/off, lock/unlock) |
| `isAppInactive({packageId, ...})` | `true` if the app has had no foreground activity |
| `getAppStandbyBucket({cancelToken, timeout})` | Standby bucket of the calling app |

All `UsageStatsManager` methods throw `PauzaUnsupportedError` on iOS.

---

## Key Types

### AppIdentifier

Opaque, cross-platform app identity:

```dart
// Android — package name
final id = AppIdentifier.android('com.instagram.android');

// iOS — base64-encoded FamilyActivityToken
final id = AppIdentifier.ios(base64EncodedToken);
```

### RestrictionMode

```dart
RestrictionMode(
  modeId: 'work',
  blockedAppIds: [AppIdentifier.android('com.twitter.android')],
  schedule: RestrictionSchedule(
    daysOfWeekIso: [1, 2, 3, 4, 5], // 1 = Monday … 7 = Sunday
    startMinutes: 540,               // 09:00 (minutes since midnight)
    endMinutes: 1020,                // 17:00
  ),
)
```

### RestrictionState

Returned by `getRestrictionSession()`:

| Field | Type | Description |
|-------|------|-------------|
| `activeMode` | `RestrictionMode?` | Currently enforced mode, or `null` |
| `activeModeSource` | `RestrictionModeSource` | `none`, `manual`, or `schedule` |
| `isActiveNow` | `bool` | `activeMode != null` |
| `isPausedNow` | `bool` | `pausedUntil != null` |
| `pausedUntil` | `DateTime?` | When the current pause expires |
| `startedAt` | `DateTime?` | When the current session began |
| `isScheduleEnabled` | `bool` | Whether schedule enforcement is on |
| `isInScheduleNow` | `bool` | Whether the current time falls in a scheduled interval |

### ShieldConfiguration

```dart
ShieldConfiguration(
  appGroupId: 'group.com.example.app', // iOS: must match your App Group ID
  title: 'Time to focus',
  subtitle: 'This app is blocked during your focus session',
  primaryButtonLabel: 'Ask for more time',
  primaryButtonBackgroundColor: const Color(0xFF1A1A2E),
  primaryButtonTextColor: Colors.white,
)
```

---

## Error Handling

All manager methods throw typed `PauzaError` subclasses on failure. Catch them to provide meaningful feedback to the user:

```dart
try {
  await restrictions.startSession(mode, duration: const Duration(minutes: 30));
} on PauzaMissingPermissionError catch (e) {
  // Guide the user to grant the missing permission
  await permissionManager.openAndroidPermissionSettings(AndroidPermission.accessibility);
} on PauzaUnsupportedError catch (e) {
  // Feature unavailable on this OS version
} on PauzaInvalidArgumentError catch (e) {
  // Bad argument — check e.message for details
} on PauzaError catch (e) {
  // Catch-all for any other plugin error
  print('${e.code}: ${e.message}');
}
```

| Class | Code | When thrown |
|-------|------|-------------|
| `PauzaUnsupportedError` | `UNSUPPORTED` | Feature not available on this platform or OS version |
| `PauzaMissingPermissionError` | `MISSING_PERMISSION` | Required permission has not been granted |
| `PauzaPermissionDeniedError` | `PERMISSION_DENIED` | Permission was explicitly denied |
| `PauzaSystemRestrictedError` | `SYSTEM_RESTRICTED` | OS policy prevents the operation |
| `PauzaInvalidArgumentError` | `INVALID_ARGUMENT` | Invalid parameter or precondition violation |
| `PauzaInternalFailureError` | `INTERNAL_FAILURE` | Unexpected native error |

---

## Running the Example App

The `example/` directory contains a working demo app.

```bash
cd example
flutter pub get
```

**Android:**

```bash
flutter run -d <android-device-id>
```

**iOS** (macOS only, physical device required):

```bash
flutter run -d <ios-device-id>
```

List available devices:

```bash
flutter devices
```

> The iOS Simulator does not support Family Controls. Always use a real device for iOS testing.

---

## Running Tests

### Dart / Flutter unit tests

Run all Dart tests from the plugin root:

```bash
flutter test
```

Run a single test file:

```bash
flutter test test/pauza_error_test.dart
```

### Android native unit tests (JVM)

```bash
# Run all Android JVM tests
make test-android

# Run a specific test class
make test-android TEST=RestrictionModeSourceTest
```

### What is tested

| Area | Test files |
|------|-----------|
| Error model and hierarchy | `test/pauza_error_test.dart`, `test/manager_error_throwing_test.dart` |
| App info serialization | `test/app_info_model_test.dart` |
| Usage stats serialization | `test/usage_stats_model_test.dart` |
| Restriction schedule model | `test/restriction_schedule_model_test.dart` |
| Restriction session state machine | `test/restrictions_session_test.dart` |
| Scheduled modes config | `test/restriction_scheduled_modes_config_test.dart` |
| Shield configuration | `test/shield_configuration_test.dart` |
| Permission logic (exact alarm edge cases) | `test/permissions_exact_alarm_test.dart` |
| Fresh-install default state contract | `test/fresh_install_contract_test.dart` |
| Method channel decode failures | `test/manager_decode_failure_test.dart` |
| Android native unit tests | `android/src/test/kotlin/` |

---

## Breaking API Changes

Previous method names and their replacements:

| Old | New |
|-----|-----|
| `restrictApps` / `restrictApp` / `unrestrictApp` / `clearAllRestrictions` | `upsertMode` + `removeMode` |
| `upsertScheduledMode` / `removeScheduledMode` | `upsertMode` / `removeMode` |
| `setScheduledModesEnabled` / `getScheduledModesConfig` | `setScheduleEnforcementEnabled` / `getModesConfig` |
| `startRestrictionSession(mode)` | `startSession(mode, {duration})` |
| `endRestrictionSession()` | `endSession({duration, reason})` |

---

## Platform Support

| Platform | Minimum version |
|----------|----------------|
| Android | 8.0 (API 26) |
| iOS | 16.0 |
