# Current State Specification — `pauza_screen_time`

Last reviewed: 2026-02-10  
Scope: Flutter plugin (`pauza_screen_time`) providing app restriction/blocking, installed app discovery, usage stats, and permission helpers across Android + iOS.

This document describes what is already implemented *in this repository*, how it is implemented, and the known limitations/bugs per feature (including whether each issue is fixable).

---

## 1) High-level architecture

### 1.1 Dart package layout (feature-based)

Public entrypoint: `lib/pauza_screen_time.dart`

Feature modules exported to consumers:
- `CoreManager` (core utils, debug helpers)
- `PermissionManager` (+ `PermissionHelper`)
- `InstalledAppsManager`
- `UsageStatsManager` (Android-only data)
- `AppRestrictionManager` (cross-platform API; platform implementations differ significantly)

Each feature has:
- a platform interface (`..._platform.dart`)
- a method-channel implementation (e.g. `.../method_channel/..._method_channel.dart`)
- typed models for serialization and return values

### 1.2 Method channels and platform boundary

Channel names are centralized in Dart in `lib/src/core/method_channel_names.dart`:
- `pauza_screen_time/core`
- `pauza_screen_time/permissions`
- `pauza_screen_time/installed_apps`
- `pauza_screen_time/usage_stats`
- `pauza_screen_time/restrictions`

Android native uses a single plugin entry (`android/src/main/kotlin/.../PauzaScreenTimePlugin.kt`) which registers per-feature registrars/handlers and triggers a reschedule of restriction alarms.

iOS native registers:
- Core + Permissions + InstalledApps + Restrictions method channels
- Usage report *platform view* (`pauza_screen_time/usage_report`)

### 1.3 Error model / fast-failure mechanism

Dart defines a sealed exception taxonomy in `lib/src/core/pauza_error.dart`:
- `UNSUPPORTED`
- `MISSING_PERMISSION`
- `PERMISSION_DENIED`
- `SYSTEM_RESTRICTED`
- `INVALID_ARGUMENT`
- `INTERNAL_FAILURE`

Feature managers call `.throwTypedPauzaError()` to translate platform exceptions into typed Dart errors.

Native layers:
- Android: `android/.../core/PluginErrors.kt` + `PluginErrorHelper` emit structured error details (feature/action/platform + optional missing/status/diagnostic).
- iOS: `ios/Classes/Core/PluginErrors.swift` emits `FlutterError` with the same taxonomy (includes `UNSUPPORTED` on iOS).

### 1.4 Background decoding for large payloads (Android)

`lib/src/core/background_channel_runner.dart` runs selected method-channel calls on a background isolate to avoid UI-isolate jank when decoding large lists (e.g., installed apps and usage stats with icons).

Known design constraints:
- Calls must return isolate-sendable values (primitives, collections, `Uint8List`).
- A single worker isolate is used with an internal request queue and idle shutdown.

---

## 2) Feature matrix (implemented vs platform support)

| Feature | Dart API | Android | iOS |
|---|---|---:|---:|
| Platform version | `CoreManager.getPlatformVersion()` | ✅ | ✅ |
| Permissions helpers | `PermissionManager` / `PermissionHelper` | ✅ | ✅ (iOS 16+) |
| Installed apps | `InstalledAppsManager` | ✅ enumerate | ✅ picker tokens only |
| Usage stats as data | `UsageStatsManager` | ✅ | ❌ (intentionally unsupported) |
| Usage stats as UI | `UsageReportView` | ❌ | ✅ (iOS 16+, needs report extension) |
| Restrict / block apps | `AppRestrictionManager` | ✅ (Accessibility overlay) | ✅ (Screen Time / ManagedSettings) |
| Manual restriction session | `startSession` / `endSession` | ✅ | ✅ |
| Scheduled modes | `upsertMode(schedule)` + `setModesEnabled(true)` | ✅ (AlarmManager) | ✅ (DeviceActivity monitors; needs monitor extension for background reliability) |
| Pause enforcement | `pauseEnforcement` / `resumeEnforcement` | ✅ (AlarmManager) | ✅ (DeviceActivity monitor; needs monitor extension for background reliability) |
| Shield configuration | `configureShield(ShieldConfiguration)` | ✅ (in-app overlay UI) | ✅ (stored for Shield extension via App Group) |
| Session snapshot | `getRestrictionSession()` | ✅ | ✅ |

---

## 3) Core feature: platform version

### What exists
- Dart: `CoreManager.getPlatformVersion()`
- Android: core method channel returns Android version string.
- iOS: `CoreMethodHandler` returns `"iOS " + UIDevice.current.systemVersion`.

### Issues / limitations
- None significant.

Fixable: N/A.

---

## 4) Permissions feature

### 4.1 Public Dart API

Entry points:
- `PermissionManager` for typed platform-aware calls:
  - Android: `checkAndroidPermission(...)`, `requestAndroidPermission(...)`, `openAndroidPermissionSettings(...)`
  - iOS: `checkIOSPermission(...)`, `requestIOSPermission(...)`
- `PermissionHelper` convenience helpers for batch checks and “request first missing”.

Permission keys (wire contract) are string-based and correspond to native handlers, e.g.:
- Android: `android.usageStats`, `android.accessibility`, `android.exactAlarm`, `android.queryAllPackages`
- iOS: `ios.familyControls`, `ios.screenTime`

### 4.2 Android implementation

Files:
- `android/.../permissions/PermissionHandler.kt`
- `android/.../permissions/method_channel/PermissionsMethodHandler.kt`

Behavior:
- Usage stats: checked via `AppOpsManager(OPSTR_GET_USAGE_STATS)`.
- Accessibility: checked via `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES` containing this plugin’s accessibility service component.
- Exact alarm: checked via `AlarmManager.canScheduleExactAlarms()` on Android 12+.
- Query-all-packages: attempts to infer capability (manifest + guarded query).

### 4.3 iOS implementation

Files:
- `ios/Classes/Permissions/PermissionHandler.swift`
- `ios/Classes/Permissions/MethodChannel/PermissionsMethodHandler.swift`

Behavior:
- iOS 16+: uses `FamilyControls.AuthorizationCenter` (`requestAuthorization(for: .individual)`).
- iOS <16: legacy handler always returns denied (individual authorization unsupported).

### 4.4 Issues / limitations (with fixability)

1) Android `queryAllPackages` status may be inaccurate.
- Symptom: `checkPermission(android.queryAllPackages)` returns granted if `getInstalledApplications(...)` returns a non-empty list; on Android 11+ this can still be non-empty even without QUERY_ALL_PACKAGES (only visible packages).
- Impact: host app may believe full enumeration is available when it’s not.
- Fixable: Partially. Android does not provide a perfect “is QUERY_ALL_PACKAGES effectively granted” runtime signal; the plugin can return `unknown/notDetermined` or perform a more conservative heuristic and document Play policy constraints.

2) Android permission request flows do not return “granted” state.
- This is intentional: requests open Settings screens; apps must re-check after resume.
- Fixable: Not fully (platform constraint). Can improve developer experience with richer docs/callback patterns.

3) iOS <16 always denies.
- Matches documented platform requirement (iOS 16+).
- Fixable: No, given current intended scope (individual authorization path).

---

## 5) Installed apps feature

### 5.1 Public Dart API

Entry point: `InstalledAppsManager`

Android:
- `getAndroidInstalledApps(includeSystemApps, includeIcons, cancelToken, timeout)`
- `getAndroidAppInfo(packageId, includeIcons, cancelToken, timeout)`
- `isAndroidAppInstalled(packageId)`

iOS:
- `selectIOSApps(preSelectedApps)` → returns `IOSAppInfo` tokens only

Model:
- `AppInfo` sealed type with `AndroidAppInfo` and `IOSAppInfo` (`lib/src/features/installed_apps/model/app_info.dart`).

### 5.2 Android implementation

Files:
- `android/.../installed_apps/InstalledAppsHandler.kt`
- `android/.../installed_apps/model/InstalledAppDto.kt`
- `android/.../utils/AppInfoUtils.kt`

Behavior:
- Enumerates via `PackageManager.getInstalledApplications(...)`.
- Optionally extracts icons (PNG bytes) and attempts category classification.

Dart-side method channel uses `BackgroundChannelRunner` to decode on a background isolate.

### 5.3 iOS implementation

Files:
- `ios/Classes/InstalledApps/FamilyActivityPickerHandler.swift`
- `ios/Classes/InstalledApps/MethodChannel/InstalledAppsMethodHandler.swift`

Behavior:
- Presents `FamilyActivityPicker` (iOS 16+) and returns base64-encoded JSON `ApplicationToken` values.
- Supports pre-selection by decoding provided base64 tokens.
- Does not (and cannot) enumerate installed apps on iOS.

### 5.4 Issues / limitations (with fixability)

1) Android full enumeration depends on `QUERY_ALL_PACKAGES` and Play policy.
- Impact: Play Store submissions may be rejected if not justified; and without it, enumeration is incomplete on Android 11+.
- Fixable: Depends on product constraints. If “list all apps” is a hard requirement, it may require policy-compliant justification, enterprise distribution, or alternative UX (user-picked apps) rather than full enumeration.

2) Icons can be heavy.
- Impact: large payloads + memory pressure.
- Current mitigation: background isolate decoding.
- Fixable: Yes (pagination, streaming, reduced icon sizes, separate icon fetch API).

3) iOS app tokens are opaque.
- Impact: no app name/icon from plugin; host apps must render tokens via native UI or store custom labels.
- Fixable: No (iOS privacy constraint). Documentation/template guidance is the right approach.

---

## 6) Usage stats feature

### 6.1 Public Dart API

Android (data):
- `UsageStatsManager.getUsageStats(startDate, endDate, includeIcons, cancelToken, timeout)`
- `UsageStatsManager.getAppUsageStats(packageId, startDate, endDate, includeIcons, cancelToken, timeout)`

iOS (UI only):
- `UsageReportView` / `IOSUsageReportView` (platform view embedding a native `DeviceActivityReport`)

Model:
- `UsageStats` (`lib/src/features/usage_stats/model/app_usage_stats.dart`) includes app info + durations + launch count + timestamps.

### 6.2 Android implementation

Files:
- `android/.../usage_stats/UsageStatsHandler.kt`
- `android/.../usage_stats/method_channel/UsageStatsMethodHandler.kt`

Behavior:
- Uses `UsageStatsManager.queryUsageStats(...)` for time-in-foreground and timestamps.
- Computes “launch counts” by scanning `UsageEvents` for `ACTIVITY_RESUMED` events in the same window.
- Enriches results with `PackageManager` label/icon/category.

Errors:
- Missing usage access triggers `MISSING_PERMISSION(android.usageStats)`.

### 6.3 iOS implementation (UI)

Files:
- Dart widget: `lib/src/features/usage_stats/widget/usage_report_view.dart`
- iOS platform view: `ios/Classes/UsageStats/UsageReportContainerView.swift`

Behavior:
- Renders `DeviceActivityReport(Context(reportContext), filter: ...)`.
- Requires a Device Activity Report extension in the host app; templates are provided in `docs/templates/`.

### 6.4 Issues / limitations (with fixability)

1) iOS does not provide usage stats as data.
- Impact: cannot implement `UsageStatsManager`-style list results on iOS.
- Fixable: No (platform limitation). UI-only approach is the correct constraint.

2) Android “launch counts” may not match user expectations.
- Reason: `ACTIVITY_RESUMED` can overcount (e.g., configuration changes, multi-window, internal activity switches).
- Fixable: Partially (heuristics), but perfect accuracy is not guaranteed with public APIs.

3) Android stats may be empty even when permission is granted (OEM quirks / limited windows / doze).
- Fixable: Partially (document, allow wider windows, add diagnostics).

---

## 7) Restrict / block apps feature (modes + sessions)

### 7.1 Public Dart API and contract

Entry point: `AppRestrictionManager`

Core operations:
- `configureShield(ShieldConfiguration)`
- `upsertMode(RestrictionMode)`
- `removeMode(modeId)`
- `setModesEnabled(enabled)` (global schedule engine toggle)
- `getModesConfig()` → returns only persisted scheduled modes needed for background enforcement
- `startSession(RestrictionMode mode)` / `endSession()`
- `pauseEnforcement(Duration)` / `resumeEnforcement()`
- `isRestrictionSessionActiveNow()` / `getRestrictionSession()`

Core models:
- `RestrictionMode(modeId, blockedAppIds, schedule?)`
- `RestrictionSchedule(daysOfWeekIso, startMinutes, endMinutes)` supports spanning midnight
- `RestrictionModesConfig(enabled, modes)` includes schedule overlap validation at model level
- `RestrictionSession` snapshot includes:
  - active mode id + source (`none/manual/schedule`)
  - schedule enabled + currently inside schedule
  - pause state + `pausedUntil`

Conflict resolution rules implemented in both native platforms:
- Manual session overrides scheduled resolution.
- Scheduled resolution is “fail-safe”: if multiple scheduled modes are active, none is enforced.
- Scheduled overlaps are rejected on `upsertMode`.

### 7.2 Android implementation

Key files:
- Storage/state:
  - `android/.../app_restriction/RestrictionManager.kt` (SharedPreferences for restricted apps, pause until, active session)
  - `android/.../app_restriction/schedule/RestrictionScheduledModesStore.kt` (SharedPreferences for scheduled modes + enabled toggle)
- Foreground enforcement:
  - `android/.../app_restriction/AppMonitoringService.kt` (AccessibilityService)
  - `android/.../app_restriction/ShieldOverlayManager.kt` + Compose overlay UI in `android/.../app_restriction/overlay/`
- Scheduling/pause timers:
  - `android/.../app_restriction/alarm/RestrictionAlarmOrchestrator.kt`
  - `android/.../app_restriction/alarm/RestrictionAlarmScheduler.kt`
  - `android/.../app_restriction/alarm/RestrictionAlarmRescheduleReceiver.kt` (boot/timezone/time-change rescheduling)
- Session state resolution:
  - `android/.../app_restriction/RestrictionSessionController.kt`
  - `android/.../app_restriction/schedule/RestrictionScheduleCalculator.kt`
  - `android/.../app_restriction/schedule/RestrictionScheduledModeResolver.kt`

Behavior summary:
- Blocking UI is an in-app overlay window of type `TYPE_ACCESSIBILITY_OVERLAY` (requires Accessibility enabled).
- Manual sessions persist in SharedPreferences; enforced by the accessibility service during events and on demand.
- Scheduled sessions are enforced by alarms firing at the next schedule boundary; alarms are re-scheduled on boot/time changes.
- Pause sets `pausedUntil` and schedules an elapsed-realtime alarm; when it fires, enforcement is re-applied.

### 7.3 iOS implementation

Key files:
- Enforcement:
  - `ios/Classes/AppRestriction/ShieldManager.swift` (ManagedSettingsStore.shield.applications)
- Storage:
  - `ios/Classes/AppRestriction/RestrictionStateStore.swift` (App Group UserDefaults for pause/session/modes)
  - `ios/Classes/AppRestriction/AppGroupStore.swift` (App Group resolution rules)
- Schedule/pause monitors:
  - `ios/Classes/AppRestriction/RestrictionScheduleMonitorOrchestrator.swift` (DeviceActivityCenter monitors per schedule)
  - `ios/Classes/AppRestriction/PauseAutoResumeMonitor.swift` (single non-repeating DeviceActivity schedule for pause auto-resume)
- Method channel routing:
  - `ios/Classes/AppRestriction/MethodChannel/RestrictionsMethodHandler.swift`
- Shield configuration storage for extension:
  - `ios/Classes/AppRestriction/ShieldConfigurationStore.swift`
  - `ios/Classes/AppRestriction/ShieldConfigurationExtension.swift` (data source for Shield Configuration extension)

Behavior summary:
- Restrictions apply via ManagedSettings; app identifiers are base64 `ApplicationToken` strings.
- Manual session is stored in App Group defaults; restrictions are applied/cleared by `applyDesiredRestrictionsIfNeeded()`.
- Scheduled modes are stored in App Group defaults; DeviceActivity monitors are scheduled to provide boundary callbacks.
- Reliable background pause auto-resume and schedule enforcement require a **Device Activity Monitor extension** in the host app.
  - A template exists: `docs/templates/PauzaDeviceActivityMonitorExtension.swift`.

### 7.4 Issues / limitations (with fixability)

1) Missing-permission fast-failure for restrictions is incomplete (both platforms).
- Android: restriction APIs (`startSession`, `upsertMode`, etc.) do not fail when Accessibility is disabled; they may “succeed” but enforcement will not happen.
- iOS: restriction APIs do not consistently return `MISSING_PERMISSION`/`PERMISSION_DENIED` when Screen Time authorization is not approved; instead `applyDesiredRestrictionsIfNeeded()` clears restrictions.
- Impact: violates “Honest Fast-Failure” requirement for this feature and can confuse the host app.
- Fixable: Yes. Both native handlers already have enough information to return typed errors:
  - Android can preflight `PermissionHandler.ACCESSIBILITY_KEY`.
  - iOS has `restrictionPreflightError(action:)` helper already implemented but currently unused.

2) iOS schedule + pause “reliability” depends on host app extensions.
- Without the Device Activity Monitor extension, background re-enforcement on schedule boundaries/pause end is not guaranteed.
- Impact: the plugin alone cannot satisfy “enforce while app terminated” on iOS.
- Fixable: Yes at the product integration level (host app must add extensions). The plugin provides templates + docs, but cannot ship the extension inside a Flutter plugin binary.

3) Android schedule/pause timing can degrade if exact alarms are denied.
- Alarm scheduler falls back to inexact alarms if exact scheduling is not allowed on Android 12+.
- Impact: “exactly when pause expires” and strict schedule boundaries may drift.
- Fixable: Partially. The app can require/guide enabling exact alarms, but device/OS policies may still interfere.

4) Android shield configuration is not persisted.
- Android `ShieldOverlayManager` stores `ShieldConfig` in-memory only.
- Impact: after process death, the shield overlay uses defaults until reconfigured.
- Fixable: Yes (persist `ShieldConfig` into SharedPreferences and load on init).

5) Docs imply Android restriction calls can throw `MISSING_PERMISSION`, but the current Android restriction method handler does not enforce this.
- Impact: documentation mismatch.
- Fixable: Yes (either implement preflight errors or update docs).

---

## 8) Documentation and templates

Documentation exists under `docs/`:
- `docs/getting-started.md`
- `docs/android-setup.md`, `docs/ios-setup.md`
- `docs/restrict-apps.md`, `docs/installed-apps.md`, `docs/usage-stats.md`, `docs/permissions.md`
- `docs/errors.md`, `docs/troubleshooting.md`

iOS integration templates exist under `docs/templates/`:
- `PauzaDeviceActivityMonitorExtension.swift` (required for reliable background pause/schedules)
- `PauzaDeviceActivityReportExtension.swift` (required for `UsageReportView`)
- `PauzaShieldConfigurationExtension.swift` (optional/recommended for custom shield UI)
- `PauzaHostAppIntegrationChecklist.md`

Known limitation:
- Templates are not compiled into the plugin; host apps must copy them into Xcode targets.

Fixable: N/A (platform packaging constraint).

---

## 9) Adherence review

### 9.1 Adherence to `specs/technical_requirements.md`

1) Strong typization — **Mostly adherent**
- Dart models are strongly typed (`RestrictionMode`, `RestrictionSession`, `UsageStats`, `AppInfo` sealed types).
- Platform payloads still use `Map` at the channel boundary (expected), but decode/normalize is implemented in model factories.
- Gap: a few places can throw non-typed exceptions (e.g., `PermissionStatus.fromString` throws `ArgumentError` for unknown values; this may surface as `INTERNAL_FAILURE` without structured diagnostics).

2) Honest fast-failure — **Partially adherent**
- Good: typed error taxonomy exists, Android usage stats properly reports `MISSING_PERMISSION`.
- Gap: restrictions feature does not consistently throw permission errors (see §7.4 #1), leading to silent/non-obvious failure modes.

3) No god class — **Adherent**
- Feature-based decomposition on Dart and native sides; clear separation between handlers, stores, schedulers, UI overlay, etc.

4) Documented — **Mostly adherent**
- README + `docs/` cover major flows and platform constraints.
- Gap: at least one doc mismatch in restrictions permission failure behavior (see §7.4 #5).

### 9.2 Adherence to `specs/specifications.md`

Core features mapping (Android / iOS):

1) Reliable manual mode — **Implemented**
- Android: active session stored; enforcement via Accessibility overlay.
- iOS: active session stored + ManagedSettings enforced; persistence depends on system behavior and/or extension on certain flows.

2) Reliable-enforced pause — **Implemented with caveats**
- Android: pause end alarm re-applies enforcement; timing may drift if exact alarms are denied; enforcement requires Accessibility running.
- iOS: implemented via DeviceActivity pause monitor; **requires** Device Activity Monitor extension for reliable background auto-resume.

3) Reliable schedules — **Implemented with caveats**
- Android: schedule boundary alarms + boot/time-change rescheduling; enforcement requires Accessibility running.
- iOS: schedule monitors are scheduled; **requires** Device Activity Monitor extension for background boundary enforcement.

4) Shield configuration — **Implemented**
- Android: customizable in-app overlay UI (not persisted across process death).
- iOS: stored to App Group for Shield Configuration extension (recommended integration path).

5) App usage statistics — **Implemented as: Android data + iOS UI**
- Android: data APIs implemented.
- iOS: UI-only report view implemented; data APIs are intentionally unsupported.

6) Applications enumeration — **Implemented as: Android enumerate + iOS picker**
- Android: full enumeration (subject to QUERY_ALL_PACKAGES and policy).
- iOS: token picker only (platform limitation).

7) Permissions — **Implemented**
- Both platforms have check/request/settings flows; iOS requires iOS 16+ for individual authorization.

8) Prioritization & conflict resolution — **Implemented**
- Single active mode enforced (manual overrides schedule; scheduled conflicts fail-safe).
- Overlapping schedules are rejected on `upsertMode` and at model-validation level.
