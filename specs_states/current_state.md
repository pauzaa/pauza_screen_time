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
  - Restricted apps set, pause deadline, and manual session toggle: `RestrictionManager` (`android/.../app_restriction/RestrictionManager.kt`)
  - Schedule config: `RestrictionScheduleStore` (`android/.../app_restriction/schedule/RestrictionScheduleStore.kt`)
  - Scheduled modes: `RestrictionScheduledModesStore` (`android/.../app_restriction/schedule/RestrictionScheduledModesStore.kt`)
- Enforcement uses:
  - `AccessibilityService` to detect foreground app changes: `AppMonitoringService` (`android/.../app_restriction/AppMonitoringService.kt`)
  - Exact/inexact alarms to enforce pause expiry and schedule boundaries: `RestrictionAlarmOrchestrator` + `RestrictionAlarmScheduler` (`android/.../app_restriction/alarm/*`)
  - Boot/time-change rescheduling: `RestrictionAlarmRescheduleReceiver` with `RECEIVE_BOOT_COMPLETED` (`android/.../alarm/RestrictionAlarmRescheduleReceiver.kt`)

**iOS**

- Persisted state uses App Group `UserDefaults`:
  - Desired restricted tokens, pause deadline, manual toggle, schedule config, scheduled modes: `RestrictionStateStore` (`ios/Classes/AppRestriction/RestrictionStateStore.swift`)
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
  - `AppRestrictionManager.startRestrictionSession()`
  - `AppRestrictionManager.endRestrictionSession()`
  - Session snapshot: `getRestrictionSession()`
- Android implementation:
  - Manual toggle is `manual_enforcement_enabled` in `RestrictionManager`.
  - `startRestrictionSession` sets it `true`; `endRestrictionSession` sets it `false`.
  - Foreground enforcement is driven by `AppMonitoringService` and a compose overlay (`ShieldOverlayManager`).
- iOS implementation:
  - Manual toggle stored in app group (`manualEnforcementEnabledKey`).
  - Enforcement applies `ManagedSettingsStore().shield.applications`.

**Adherence to `specs/specifications.md`**

- Start/End: ✅ implemented
- Persistence across app exit / reboot: ⚠️
  - Android: ✅ persisted in `SharedPreferences`, alarms rescheduled on boot; relies on AccessibilityService being enabled (user/system can disable it).
  - iOS: ✅ persisted in app group; restrictions persist via ManagedSettings; relies on Screen Time authorization.
- “Termination”: ✅ scheduled boundaries do not flip manual state; manual must be ended by `endRestrictionSession()`.

**Gaps / caveats**

- Spec talks about “Mode” as a first-class object. Manual mode here is a **global boolean** + a **global restricted apps set**, not a typed “Mode” with its own identity.
  - Fixability: ✅ fixable (add a typed Mode concept + store “activeModeId” + mode-specific blocked apps), but it’s an API/design change.

Status vs specs: **⚠️ (meets practical behavior, but Mode concept is not represented as an object)**

---

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

There are **two schedule APIs** in this codebase:

1) Legacy schedule config: `setRestrictionScheduleConfig(RestrictionScheduleConfig)`
2) Mode-based schedule config: `upsertScheduledMode(RestrictionScheduledMode)` + `setScheduledModesEnabled(true)`

#### 2.3.1 Mode-based schedules (“one mode → one schedule”)

**What exists**

- Dart: `RestrictionScheduledMode` (modeId, enabled flag, schedule, blockedAppIds)
- Android:
  - Persisted in `RestrictionScheduledModesStore`.
  - Overlap is validated at write time (rejects overlap).
  - Schedule boundary alarms are scheduled/rescheduled by `RestrictionAlarmOrchestrator`.
  - At enforcement time, `RestrictionScheduledModeResolver.resolveNow(...)` must match **exactly one** active mode; otherwise it resolves to “no schedule active”.
- iOS:
  - Persisted in app group (`RestrictionStateStore.storeScheduledModes`).
  - Overlap is validated (`RestrictionScheduleEvaluator.isScheduleShapeValid`).
  - Monitoring scheduled via `DeviceActivityCenter` (`RestrictionScheduleMonitorOrchestrator.rescheduleMonitors()`).

**Adherence to `specs/specifications.md`**

- “Schedules automatically enable/disable”: ⚠️
  - Android: ✅ if manual session is disabled (`endRestrictionSession()`), since manual override takes precedence.
  - iOS: ⚠️ requires a host Device Activity Monitor extension to apply/clear restrictions at boundary times while app is not running.
- “Persistence across reboot”: ⚠️
  - Android: ✅ alarms rescheduled on boot and time changes.
  - iOS: ⚠️ depends on monitor persistence + host extension + app group state being correct.
- “No overlapping schedules across modes”: ✅ enforced on both platforms.
- “Only one mode active at a time”: ✅ by non-overlap enforcement; resolvers fail-safe to “none” if multiple match.

Status vs specs: **⚠️ (Android strong; iOS depends on host extension)**

#### 2.3.2 Legacy schedules (`setRestrictionScheduleConfig`)

**Intent**

The docs claim this config enables/disables restriction enforcement based on weekly windows.

**Current Android behavior appears logically broken**

Android’s legacy schedule flow reuses the **same persisted restricted-apps set** as both:

- the “desired list” to apply inside schedule windows, and
- the “currently applied list” to clear outside windows

Concretely:

- When manual session is disabled, schedule boundary handling can call `RestrictionManager.setRestrictedApps(...)` with an empty list when leaving the schedule window.
- On the next schedule start, legacy logic reads the restricted apps list again to re-apply it — but it has already been cleared, so nothing re-applies.

This makes “legacy schedule toggling” non-persistent across schedule cycles unless the host app re-writes restricted apps before each cycle (which conflicts with the “works when app isn’t running” requirement).

Fixability: ✅ fixable (store “desiredRestrictedApps” separately on Android, like iOS does, or avoid mutating the desired set when leaving a window).

**iOS legacy schedules**

iOS stores schedule windows separately and does not overwrite the desired token list; enforcement uses `applyDesiredRestrictionsIfNeeded()` to decide what should be applied.

Fixability: N/A (iOS has the separation; background enforcement still requires host extension).

Status vs specs: **Android legacy schedule = ❌ (as implemented today); scheduled modes = ⚠️**

---

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
  - Query all packages “capability check”
- iOS:
  - `PermissionHandler` requests FamilyControls authorization (`AuthorizationCenter.shared.requestAuthorization(for: .individual)`)
  - iOS < 16 fallback always returns denied

**Adherence to specs**

- ✅ Implemented with typed API and platform handlers.

Status vs specs: **✅**

---

### 2.8 Prioritization & Conflict Resolution

**What exists**

- “Single active mode”: enforced primarily by **non-overlapping schedules** for scheduled modes.
  - Dart models include `isValid` checks (`RestrictionScheduleConfig.isValid`, `RestrictionScheduledModesConfig.isValid`).
  - Native layers enforce overlap constraints and return `INVALID_ARGUMENT` when violated.
- “Manual override precedence”:
  - Both platforms treat manual session as an override: if manual is enabled, schedule-based mode switching is ignored.

**Gaps**

- There is no first-class “active mode id” returned by `RestrictionSession`.
  - Host can only infer by inspecting `restrictedApps`, not by reading “activeModeId”.
  - Fixability: ✅ add `activeModeId` / `activeModeSource` to session payloads.

Status vs specs: **⚠️**

---

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

Partially compliant; there are several places where errors are **caught and converted into “empty success”** instead of a typed error:

- Dart restrictions method channel:
  - `getRestrictionScheduleConfig()`, `getRestrictionSession()`, and `getScheduledModesConfig()` swallow parse failures and return default values.
- Android installed apps and usage stats handlers:
  - `InstalledAppsHandler.getInstalledApps()` logs and returns `[]` on exception.
  - `UsageStatsHandler.calculateLaunchCounts()` logs errors and returns partial results.

Where it *is* compliant:

- Permission preflight and restrictions prerequisites are surfaced as stable taxonomy codes (`MISSING_PERMISSION`, `PERMISSION_DENIED`, etc.).
- iOS restrictions fail fast on invalid token decoding and on missing authorization (typed errors).

Fixability:

- ✅ fixable to make “parse failure” and “native exception” paths throw typed errors instead of returning default/empty results.

Status: **⚠️**

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

### 4.1 iOS compile-time bug in schedule monitor orchestrator

- File: `ios/Classes/AppRestriction/RestrictionScheduleMonitorOrchestrator.swift`
- Problem: `scheduleEnabled = enabled` references an undefined symbol `enabled`.
- Impact: iOS build should fail for this target.
- Fixability: ✅ fixable (likely meant `RestrictionStateStore.loadScheduleEnabled()`).

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

### 4.4 Android legacy schedule config appears non-functional across cycles

As described in §2.3.2, the legacy schedule implementation clears the same restricted-apps list it later needs to re-apply.

Fixability: ✅ fixable (separate “desired restrictions” from “applied restrictions” on Android, mirroring iOS, or redesign legacy schedule logic).

### 4.5 Play Store / policy risk: `QUERY_ALL_PACKAGES` and exact alarms

- The plugin manifest includes `android.permission.QUERY_ALL_PACKAGES` and `android.permission.SCHEDULE_EXACT_ALARM`.
- Depending on distribution/policy, host apps may not be allowed to ship with these unless justified.

Fixability: ⚠️ depends on product/policy. Technically fixable (reduce scope using `<queries>` or user flows), but may reduce functionality.

### 4.6 Silent fallback behaviors conflict with “fast-failure”

Examples:

- Dart restrictions getters default silently on malformed payloads.
- Android installed apps handler returns empty list on errors.

Fixability: ✅ fixable by returning typed `PauzaError` consistently.

### 4.7 Stray file in Android sources

- File: `android/src/main/kotlin/com/example/pauza_screen_time/permissions/method_channel/Untitled`
- Impact: likely harmless (no `.kt` extension), but confusing and should be removed.
- Fixability: ✅ fixable (delete file).

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

- Scheduled modes exist as a typed object (`RestrictionScheduledMode`), but manual mode is a boolean toggle without mode identity.
- `RestrictionSession` does not expose an “active mode id” or “source” (manual vs schedule vs which scheduled mode).

Fixability: ✅ fixable (API/design change): add a typed Mode model (or at least add `activeModeId` + `activeModeSource` to the session snapshot).

---

## 6) Bottom line

- The plugin has a solid feature-based architecture and typed Dart API surface.
- Android restrictions + pause + scheduled modes are implemented with persistence and background enforcement, but schedule timing may degrade without exact alarms.
- iOS restrictions APIs exist and are strongly typed around Screen Time authorization and token decoding, but **reliable background schedule/pause enforcement requires host extensions**, and there is a **blocking compile-time bug** in schedule monitor orchestration.
- Some areas (notably parse fallbacks and “return empty on error”) do not adhere to the “Honest Fast-Failure” technical requirement.

