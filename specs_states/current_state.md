# Current State (pauza_screen_time)

Date of analysis: **2026-02-09**

This document summarizes what is implemented in the codebase **right now**, how each feature works, and how the implementation aligns with:

- `specs/specifications.md`
- `specs/technical_requirements.md`

It also highlights missing spec features, likely errors/pitfalls, and whether each issue is fixable.

---

## 0) Scope / What was reviewed

- Dart public API and models in `lib/`
- Android implementation in `android/src/main/kotlin/...`
- iOS implementation in `ios/Classes/...`
- Plugin documentation in `README.md` + `docs/`
- Dart unit tests in `test/`
- Tooling check results:
  - `dart analyze`: **No issues found**
  - `flutter test`: **All tests passed**

---

## 1) High-level architecture

### 1.1 Dart API surface (host-app facing)

The package exports feature modules from `lib/pauza_screen_time.dart`:

- Core: `CoreManager` (platform version, common channel utilities)
- Permissions: `PermissionManager`
- Installed apps: `InstalledAppsManager`
- Restrictions/blocking: `AppRestrictionManager`
- Usage stats:
  - Android data APIs: `UsageStatsManager`
  - iOS UI report: `UsageReportView` / `IOSUsageReportView` (platform view)

Each feature is implemented as:

- A typed Dart “manager” class (in `lib/src/features/**/data/*_manager.dart`)
- A platform interface (in `lib/src/features/**/*_platform.dart`)
- A method-channel implementation (in `lib/src/features/**/method_channel/*_method_channel.dart`)
- Typed models with `toMap()` / `fromMap()` for channel payloads

Performance-oriented detail:

- Heavy method-channel decoding (e.g. installed apps / usage stats with icons) is routed through `BackgroundChannelRunner` (`lib/src/core/background_channel_runner.dart`) to move decode work off the UI isolate.

### 1.2 Native implementation pattern

- Android: Kotlin handlers registered in `android/src/main/kotlin/.../*ChannelRegistrar.kt` and dispatched by `*MethodHandler.kt`.
- iOS: Swift registrars in `ios/Classes/**/MethodChannel/*Registrar.swift` + method handlers (notably `ios/Classes/AppRestriction/MethodChannel/RestrictionsMethodHandler.swift`).

### 1.3 Persistence / “keeps working when app is closed”

**Android**

- Restrictions state is stored in `SharedPreferences`:
  - Blocked apps list, pause deadline, and active manual `modeId`: `RestrictionManager` (`android/.../app_restriction/RestrictionManager.kt`)
  - Mode catalog plus schedule toggle: `RestrictionScheduledModesStore` (`android/.../app_restriction/schedule/RestrictionScheduledModesStore.kt`)
- Enforcement uses:
  - `AccessibilityService` to detect foreground app changes: `AppMonitoringService` (`android/.../app_restriction/AppMonitoringService.kt`)
  - Exact/inexact alarms to enforce pause expiry and schedule boundaries: `RestrictionAlarmOrchestrator` + `RestrictionAlarmScheduler` (`android/.../app_restriction/alarm/*`)
  - Boot/time-change rescheduling: `RestrictionAlarmRescheduleReceiver` with `RECEIVE_BOOT_COMPLETED` (`android/.../alarm/RestrictionAlarmRescheduleReceiver.kt`)

**iOS**

- Persisted state uses App Group `UserDefaults`:
  - Mode catalog, schedule toggle, manual `modeId`, and pause deadline: `RestrictionStateStore` (`ios/Classes/AppRestriction/RestrictionStateStore.swift`)
  - Shield UI configuration: `ShieldConfigurationStore` (`ios/Classes/AppRestriction/ShieldConfigurationStore.swift`)
- Enforcement uses:
  - ManagedSettings shield restrictions: `ShieldManager` (`ios/Classes/AppRestriction/ShieldManager.swift`)
  - DeviceActivity monitoring for schedules and pause auto-resume: `RestrictionScheduleMonitorOrchestrator` and `PauseAutoResumeMonitor`
    - Important: these monitors only become “reliable background enforcement” when the **host app includes the required iOS extensions** (see “Pitfalls”).

---

## 2) Specs compliance: feature-by-feature

Legend:

- ✅ Meets spec intent
- ⚠️ Partially meets / caveats
- ❌ Missing (and whether fixable is called out)

### 2.1 Reliable Manual Mode (start/end, persistence, manual termination only)

**What exists**

- Dart API:
  - `upsertMode`, `removeMode`, `setModesEnabled`, `getModesConfig`
  - `startModeSession(modeId)` / `endModeSession()`
  - `getRestrictionSession()` now surfaces `activeModeId` / `activeModeSource`
- Android implementation:
  - `RestrictionManager` stores `manualActiveModeId` instead of a boolean toggle
  - Manual session startup validates the mode before writing the `modeId`
  - Enforcement resolves manual mode first, then scheduled resolution if none
- iOS implementation:
  - `RestrictionStateStore` keeps the entire mode catalog, toggle, and `manualActiveModeId`
  - Manual session writes to App Group defaults and re-applies the matching mode blocklist
  - `RestrictionScheduledModeEvaluator` now returns the matched `modeId` along with blocked apps

**Adherence to `specs/specifications.md`**

- Start/End: ✅ manual session APIs now explicitly target a named mode
- Persistence across app exit / reboot: ⚠️
  - Android: ✅ persisted `modeId`; AccessibilityService re-applies the stored mode when it wakes
  - iOS: ✅ App Group storage; relies on Device Activity Monitor extension for background enforcement
- “Termination”: ✅ manual session only ends when `endModeSession()` clears the stored `modeId`

**Gaps / caveats**

- Migration risk: the legacy helpers (`restrictApps`, `restrictApp`, `clearAllRestrictions`, scheduled-mode helpers) were removed; hosts must now use the mode-centric APIs documented in README/docs.
  - Fixability: ⚠️ breaking but documented in README/docs with a clear mapping.

Status vs specs: **⚠️ (behaviorally compliant once migrated; host apps need to adopt the new API surface)**
### 2.2 Reliable-Enforced Pause (fixed duration, auto re-enforce, survives reboot)

**What exists**

- Dart API: `pauseEnforcement(Duration)`, `resumeEnforcement()`, and session snapshot fields (`isPausedNow`, `pausedUntil`).

**Android**

- Pause state stored in `RestrictionManager` (`paused_until_epoch_ms`).
- Auto resume is implemented via an alarm:
  - `RestrictionAlarmType.PAUSE_END` scheduled by `RestrictionAlarmOrchestrator`.
  - When fired, it calls `AppMonitoringService.getInstance()?.enforceCurrentForegroundNow(...)` to immediately re-block if the user is still inside a restricted app.
- Reboot persistence: `RestrictionAlarmRescheduleReceiver` re-schedules pause-end alarms after boot/time changes.

**iOS**

- Pause state is stored in app group (`pausedUntilEpochMsKey`) and cleared if stale.
- `pauseEnforcement`:
  - Writes paused-until timestamp.
  - Starts a `DeviceActivityCenter` monitor (`PauseAutoResumeMonitor.startMonitoring`).
  - Clears current ManagedSettings restrictions immediately.
- iOS enforces an upper bound: duration must be `< 24h`.

**Adherence to `specs/specifications.md`**

- Android: ⚠️ largely aligned, with timing caveats (see pitfalls).
- iOS: ⚠️ API exists, but reliability depends on host extension (see pitfalls).

**Key pitfalls**

- Android “exactly when pause ends” is not guaranteed on Android 12+ unless the app is allowed to schedule exact alarms.
  - Implementation falls back to inexact alarms if exact scheduling is denied (`RestrictionAlarmScheduler.scheduleExactOrFallback`).
  - Fixability: ⚠️ partially fixable (detect/report exact-alarm capability and document “may be delayed”). True “exact” is OS/policy-dependent.
- iOS “re-enforce when pause expires while app is terminated” is not implemented inside the plugin alone.
  - It requires a **Device Activity Monitor extension** in the host app to receive the callback and re-apply restrictions based on stored state.
  - Fixability: ✅ fixable as a host integration requirement (templates exist under `docs/templates/`), but not solvable purely in the plugin runtime.

Status vs specs: **⚠️**

---

### 2.3 Reliable Schedules (auto enable/disable without app running, persists reboot)

Schedule configuration is now **mode-only**: each `RestrictionMode` can optionally include a schedule, and the mode catalog is the single source of truth.

- Modes are stored through `upsertMode(mode)` / `removeMode(modeId)` and a global `setModesEnabled(bool)` toggle.
- The catalog plus toggle is exposed via `getModesConfig()` (new model `RestrictionModesConfig`).
- `RestrictionScheduledModeResolver` and `RestrictionScheduledModeEvaluator` now return the active `modeId` and blocked apps when a scheduled mode is currently active.

**Adherence to `specs/specifications.md`**

- “Schedules automatically enable/disable”: ⚠️
  - Android: ✅ mode-based config drives alarms and enforcement when no manual session overrides it.
  - iOS: ⚠️ background enforcement still depends on the host Device Activity Monitor extension.
- “Persistence across reboot”: ⚠️
  - Android: ✅ alarms and stored modes/TL toggle survive reboots.
  - iOS: ⚠️ App Group storage persists the catalog, but Device Activity monitors must be re-registered on extension startup.
- “No overlapping schedules across modes”: ✅ enforced via shape validation in `RestrictionModesConfig.isValid` and native validators.
- “Only one mode active at a time”: ✅ resolver returns `none` when multiple scheduled modes match, preventing ambiguity.

Status vs specs: **⚠️ (mode-based behavior is correct; iOS still needs host extension for full reliability)**
### 2.4 Shield Configuration (custom appearance/content)

**What exists**

- Dart model: `ShieldConfiguration` (`lib/src/features/restrict_apps/model/shield_configuration.dart`)
- Dart API: `AppRestrictionManager.configureShield(...)`

**Android**

- `ShieldOverlayManager` stores a typed `ShieldConfig` and renders a full-screen compose overlay (`ShieldOverlayContent`).
- Uses `WindowManager.LayoutParams.TYPE_ACCESSIBILITY_OVERLAY` (so AccessibilityService is a prerequisite).

**iOS**

- `configureShield` stores configuration in App Group `UserDefaults`.
- A Shield Configuration extension can read it via `ShieldConfigurationStore` and render a `ManagedSettingsUI.ShieldConfiguration` via `ShieldConfigurationExtension`.

**Adherence to `specs/specifications.md`**

- ✅ implemented on both platforms, with iOS requiring a host extension to actually render a custom shield UI.

Key pitfalls:

- iOS will fail if App Group is not configured (typed error is returned).
  - Fixability: ✅ host setup.

Status vs specs: **✅**

---

### 2.5 App Usage Statistics (screen time for a date-time period)

**What exists**

- Android data API:
  - Dart: `UsageStatsManager.getUsageStats(...)`, `getAppUsageStats(...)`
  - Android: `UsageStatsHandler` using `UsageStatsManager` + `queryEvents` for launch counts
- iOS UI-only API:
  - Dart widget: `UsageReportView` embedding an iOS `DeviceActivityReport` platform view

**Adherence to `specs/specifications.md`**

- Android: ✅ provides a programmatic “get usage stats for a range” API.
- iOS: ❌ cannot provide programmatic usage stats due to Apple platform limitations; implemented as UI-only report.
  - Fixability: ❌ not fixable as a plugin feature without violating platform constraints; best possible is the current UI embedding.

Status vs specs: **⚠️ overall (Android meets, iOS constrained)**

---

### 2.6 Applications Enumeration (list installed apps)

**What exists**

- Android:
  - Dart: `InstalledAppsManager.getAndroidInstalledApps(...)`, `getAndroidAppInfo(...)`
  - Kotlin: `InstalledAppsHandler` using `PackageManager.getInstalledApplications(...)`
- iOS:
  - Dart: `InstalledAppsManager.selectIOSApps(...)` returns opaque selection tokens
  - Swift: `FamilyActivityPickerHandler` presents `FamilyActivityPicker` and serializes tokens

**Adherence to `specs/specifications.md`**

- Android: ✅ enumerates installed apps.
- iOS: ❌ listing installed apps is not available; only picker tokens can be obtained.
  - Fixability: ❌ not fixable due to platform restrictions.

Status vs specs: **⚠️ overall (Android meets, iOS constrained)**

---

### 2.7 Permissions (request/check all required permissions)

**What exists**

- Dart: `PermissionManager` with typed enums (`AndroidPermission`, `IOSPermission`) and typed `PermissionStatus`.
- Android: `PermissionHandler` supports:
  - Usage access (AppOps check + settings intent)
  - Accessibility enabled check + settings intent
  - Exact alarm capability (API 31+ gate) via `AlarmManager.canScheduleExactAlarms()` check + `ACTION_REQUEST_SCHEDULE_EXACT_ALARM` intent; API < 31 treated as granted
  - Query all packages “capability check”
- iOS:
  - `PermissionHandler` requests FamilyControls authorization (`AuthorizationCenter.shared.requestAuthorization(for: .individual)`)
  - iOS < 16 fallback always returns denied

**Adherence to specs**

- ✅ Implemented with typed API and platform handlers.
- ⚠️ Exact alarm capability is now part of the runtime permission flow; lacking exact alarms degrades schedule/pause timing because the plugin falls back to inexact alarms, but enforcement still works.

Status vs specs: **✅**

---

### 2.8 Prioritization & Conflict Resolution

- “Single active mode”: enforced by the combination of `RestrictionModesConfig.isValid` (no overlapping schedules) and the resolver returning a single `modeId`; the new session payload makes it obvious which mode is currently enforcing.
- “Manual override precedence”: manual `modeId` stored by `startModeSession()` supersedes any scheduled resolution until `endModeSession()` clears it.
- Conflict detection happens during `upsertMode()` and `setModesEnabled(true)` through native validators, returning `INVALID_ARGUMENT` when overlaps are detected.
- The `RestrictionSession` now returns `activeModeId` + `activeModeSource` (`none`, `manual`, `schedule`), so hosts no longer need to infer the active mode from `restrictedApps`.

Status vs specs: **✅ (mode identity is first-class and exposed to hosts)**
## 3) Technical requirements compliance (`specs/technical_requirements.md`)

### 3.1 Strong Typization

Mostly compliant:

- Dart side uses typed managers and typed models (`UsageStats`, `RestrictionSession`, etc.).
- Native side generally uses structured models for schedules and scheduled modes:
  - Android schedule types: `RestrictionScheduleEntry`, `RestrictionScheduledModeEntry`, `RestrictionScheduledModesConfig`
  - iOS schedule types: `RestrictionSchedule`, `RestrictionScheduledMode`

Notable caveats:

- Method-channel boundaries necessarily use maps/lists; some parsing relies on runtime casts (`fromMap` patterns).
- Android storage of restricted apps uses JSON in SharedPreferences (`RestrictionManager`).

Status: **✅ / ⚠️ (good overall; map parsing is the main weak spot)**

### 3.2 Honest Fast-Failure

✅ Now compliant: decoding failures no longer default to empty objects. `getRestrictionSession()` and `getScheduledModesConfig()` throw typed `INTERNAL_FAILURE` errors when the native payloads are null or malformed, Android installed-apps enumeration surfaces decode/parsing faults as typed errors instead of `[]`, and usage-stats handler failures propagate through `INTERNAL_FAILURE` rather than logging and returning partial results.

Where it *is* compliant:

- Permission preflight and restrictions prerequisites surface stable taxonomy codes (`MISSING_PERMISSION`, `PERMISSION_DENIED`, etc.).
- iOS restrictions continue to fail fast on invalid token decoding and missing authorization.

Status: **✅**

### 3.3 No God Class

Compliant:

- Feature modules are separated on Dart and native sides.
- The largest classes (`RestrictionsMethodHandler` on Android/iOS) are big but still feature-scoped.

Status: **✅**

### 3.4 Documented

Compliant at the project level:

- `README.md` and `docs/` provide setup and limitation documentation.

Partial within code:

- Many classes/methods are documented, but some complex behaviors (notably schedule/manual interactions) are not fully explained at the code level.

Status: **✅ / ⚠️**

---

## 4) Likely errors / pitfalls (and fixability)

### 4.1 Legacy schedule stack removed (breaking)

- Legacy schedule API (`setRestrictionScheduleConfig` / `getRestrictionScheduleConfig`) was removed from Dart and native channels.
- Runtime schedule resolution on Android and iOS now relies only on scheduled modes (`RestrictionScheduledModesStore` / scheduled modes in `RestrictionStateStore`).
- Impact: host apps must use scheduled-mode APIs; old legacy calls no longer exist.
- Fixability: N/A (intentional breaking change aligned with one-app-centric architecture).

### 4.2 iOS “reliable schedules” and “reliable pause auto-resume” require host extensions

The plugin schedules `DeviceActivityCenter` monitors, but on iOS the system calls into a **Device Activity Monitor extension** (and a **Device Activity Report extension** for UI reports). Without them:

- pause may not auto-resume when the app is terminated/backgrounded
- schedule boundaries will not be enforced while the app is not running
- usage stats UI may fail to render expected contexts

Fixability: ✅ fixable as host app integration requirements (templates exist under `docs/templates/`), but not solvable by Dart-only changes.

### 4.3 Android schedule accuracy depends on exact alarms capability

- Alarm scheduling uses exact alarms when allowed, otherwise falls back to inexact alarms.
- Impact: pause-end and schedule boundary enforcement may be delayed.
- Fixability: ⚠️ partially fixable (detect/report inability to schedule exact alarms; offer degraded-mode docs). Absolute “exact” timing cannot be guaranteed on all devices.

### 4.4 Android legacy schedule inconsistency (retired)

- This previously affected the removed legacy schedule path and is no longer applicable after legacy stack removal.

### 4.5 Play Store / policy risk: `QUERY_ALL_PACKAGES` and exact alarms

- The plugin manifest includes `android.permission.QUERY_ALL_PACKAGES` and `android.permission.SCHEDULE_EXACT_ALARM`.
- Depending on distribution/policy, host apps may not be allowed to ship with these unless justified.

Fixability: ⚠️ depends on product/policy. Technically fixable (reduce scope using `<queries>` or user flows), but may reduce functionality.

### 4.6 Silent fallback behaviors conflict with “fast-failure”

Examples:

- Dart restrictions getters now throw `INTERNAL_FAILURE` when payloads are missing or malformed instead of silently defaulting.
- Android installed apps handler surfaces decode errors as typed failures instead of returning empty lists.

Fixability: ✅ resolved by the current strict decode behavior.

---

## 5) Missing features from `specs/specifications.md`

### 5.1 iOS “usage stats as data”

- Missing by platform constraint (Apple does not provide programmatic per-app usage stats to third-party apps in the same way Android does).
- Current workaround is UI-only DeviceActivityReport.
- Fixability: ❌ not fixable under platform rules.

### 5.2 iOS “installed apps enumeration”

- Missing by platform constraint (no API to list all installed apps).
- Current workaround is picker + token storage.
- Fixability: ❌ not fixable under platform rules.

### 5.3 First-class “Mode” concept in API

Specs define “Mode” as the core object with rules “what/when/how”.

Current state:

- `RestrictionMode` / `RestrictionModesConfig` expose schedules, blocked app ids, and the catalog of configured modes.
- Manual sessions explicitly store the active `modeId` and schedule resolution returns the currently matched mode.
- `RestrictionSession` now includes `activeModeId` and `activeModeSource`.

Fixability: ✅ implemented by this release; hosts must migrate to the new mode-based APIs and read the session metadata instead of inferring the active mode indirectly.
## 6) Bottom line

- The plugin now exposes first-class modes (`RestrictionMode`, `RestrictionModesConfig`) and mode-aware APIs, replacing the old unrestricted-app helpers.
- Android and iOS persistence layers store the manual `modeId` and resolve scheduled modes with identity metadata, feeding that into `RestrictionSession.activeModeId` / `activeModeSource` plus scheduled alarm enforcement.
- iOS still depends on host Device Activity extensions for background enforcement and pause auto-resume, while Android timing relies on exact-alarm capability when available.
