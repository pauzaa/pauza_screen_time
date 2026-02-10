# Current State Specification - pauza_screen_time

## Scope and baseline

This document captures the **current implemented state** of the plugin as of this repository snapshot.

Evidence sources used:
- Dart API and models in `lib/`
- Android implementation in `android/src/main/kotlin/`
- iOS implementation in `ios/Classes/`
- Project specs in `specs/technical_requirements.md` and `specs/specifications.md`
- Tests in `test/`
- Public docs in `docs/` and `README.md`

Validation run during this analysis:
- `dart analyze` -> no issues
- `flutter test` -> all tests passed

---

## 1) Implemented Features (with implementation details)

### 1.1 Core plugin API surface

Implemented:
- Unified Dart exports via `lib/pauza_screen_time.dart`
- Feature managers:
  - `CoreManager`
  - `PermissionManager`
  - `InstalledAppsManager`
  - `AppRestrictionManager`
  - `UsageStatsManager`
- iOS usage report view widget:
  - `UsageReportView` / `IOSUsageReportView`

Implementation details:
- Architecture is feature-sliced (`core`, `permissions`, `installed_apps`, `restrict_apps`, `usage_stats`), not a monolith.
- Method channels are split per feature, each with dedicated method names and handlers.
- Heavy payload calls (installed apps and usage stats) are decoded via `BackgroundChannelRunner` to avoid UI-isolate work.

Issues / limitations:
- No issue identified in feature wiring itself.

Fixability:
- N/A

---

### 1.2 Typed error model and exception mapping

Implemented:
- Stable typed error taxonomy in Dart:
  - `PauzaUnsupportedError`
  - `PauzaMissingPermissionError`
  - `PauzaPermissionDeniedError`
  - `PauzaSystemRestrictedError`
  - `PauzaInvalidArgumentError`
  - `PauzaInternalFailureError`
- Native error helpers on Android (`PluginErrorHelper`) and iOS (`PluginErrors`) map to stable taxonomy codes.
- `throwTypedPauzaError()` extension maps platform exceptions to typed Dart errors.

Implementation details:
- Most manager calls wrap platform calls in `throwTypedPauzaError()`.
- Strict decode failures are turned into `INTERNAL_FAILURE` and propagated.
- Tests validate taxonomy mapping and typed throws.

Issues / limitations:
- Some native flows still swallow errors instead of propagating typed failures:
  - Android `PermissionHandler` catches and returns fallback booleans/status in multiple places.
  - iOS `PermissionHandler.requestFamilyControlsAuthorization` catches and returns `false` without typed diagnostic.
  - iOS plugin registration uses `try? RestrictionScheduleMonitorOrchestrator.rescheduleMonitors()` and drops startup errors.

Fixability:
- Fixable. Replace silent fallbacks with typed error propagation where operation semantics require fail-fast reporting.

---

### 1.3 Permissions feature

Implemented:
- Android permission check/request/settings-open for:
  - `usageStats`
  - `accessibility`
  - `exactAlarm`
  - `queryAllPackages` (check only, no runtime request)
- iOS permission check/request for:
  - `familyControls`
  - `screenTime` (mapped to same underlying authorization)
- Batch and helper APIs:
  - Check all/missing permissions
  - Request-first-missing flow (`PermissionHelper`)

Implementation details:
- Android:
  - Usage access check via `AppOpsManager`
  - Accessibility enabled-service check via `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES`
  - Exact-alarm capability check via `AlarmManager.canScheduleExactAlarms()` on API 31+
- iOS:
  - Authorization via `AuthorizationCenter.shared.requestAuthorization(for: .individual)`
  - iOS <16 fallback handler returns denied/false

Issues / limitations:
- Unknown permission keys on Android return `unknown` status (can hide integration mistakes if wrong key enters native side).
- iOS request flow returns `false` on errors without rich typed details.
- `PermissionHelper.requestAllRequiredPermissions()` requests only first missing item by design (sequential UX), not all at once.

Fixability:
- Unknown-key strictness: Fixable.
- iOS request diagnostics quality: Fixable.
- Request-one-at-a-time helper behavior: Intended design; fixable only if product decision changes.

---

### 1.4 Installed apps feature

Implemented:
- Android:
  - Enumerate installed apps (`getAndroidInstalledApps`)
  - Get single app info (`getAndroidAppInfo`)
  - Optional icon inclusion and system app filtering
- iOS:
  - App selection via `FamilyActivityPicker` (`selectIOSApps`)
  - Supports pre-selected app tokens

Implementation details:
- Android returns rich metadata (`packageId`, name, icon bytes, category, system-flag).
- iOS returns opaque `applicationToken` payload only (as base64), compatible with restriction APIs.
- DTO and model mapping is strongly typed on all layers.

Issues / limitations:
- iOS cannot enumerate all installed apps due platform restrictions.
- Android enumeration may be policy-limited by `QUERY_ALL_PACKAGES` behavior and Play policy constraints.

Fixability:
- iOS full enumeration: Not fixable (Apple platform restriction).
- Android policy limits: Partially fixable via product/policy adaptation (e.g., narrower package queries), not fully in plugin-only layer.

---

### 1.5 Usage stats feature

Implemented:
- Android data APIs:
  - `getUsageStats(startDate, endDate)`
  - `getAppUsageStats(packageId, startDate, endDate)`
- iOS UI-only usage reporting:
  - `UsageReportView` platform view embedding `DeviceActivityReport`

Implementation details:
- Android:
  - Pulls usage from `UsageStatsManager`
  - Computes launch count via `UsageEvents.ACTIVITY_RESUMED`
  - Enriches with app metadata/icon
  - Returns typed `UsageStats` model
  - Missing usage permission returns `MISSING_PERMISSION`
- iOS:
  - No data-returning stats API
  - Uses report context + date interval + daily/hourly segmentation in native SwiftUI view
  - Requires host report extension

Issues / limitations:
- iOS usage stats as raw data are unavailable by platform design.
- Date-range argument validation is minimal (start > end normalization exists in iOS report view but not symmetric validation at all API entry points).

Fixability:
- iOS raw data API: Not fixable (Apple platform restriction).
- Additional input validation: Fixable.

---

### 1.6 Restrict/block apps feature (modes + sessions)

Implemented:
- Shield configuration API (`configureShield`)
- Mode CRUD and global scheduling toggle:
  - `upsertMode`, `removeMode`, `setModesEnabled`, `getModesConfig`
- Manual session control:
  - `startModeSession`, `startManualModeSession`, `endModeSession`
- Pause/resume enforcement:
  - `pauseEnforcement(duration)`, `resumeEnforcement()`
- Session snapshot:
  - `getRestrictionSession()`
  - `isRestrictionSessionActiveNow()`

Implementation details:
- Android:
  - Enforcement trigger via `AccessibilityService` (`AppMonitoringService`)
  - Shield display via overlay (`TYPE_ACCESSIBILITY_OVERLAY`, Compose UI)
  - Persistence:
    - Manual active mode + pause state in SharedPreferences
    - Scheduled enforceable modes in dedicated store
  - Alarm-based orchestration for pause-end and schedule boundaries (`AlarmManager` + boot/time-change reschedule receiver)
- iOS:
  - Enforcement via `ManagedSettingsStore.shield.applications`
  - Mode/schedule/manual/pause persisted in App Group UserDefaults
  - Boundary rescheduling via `RestrictionScheduleMonitorOrchestrator` (DeviceActivity)
  - Pause auto-resume monitor (`PauseAutoResumeMonitor`) with explicit <24h guard
  - Shield customization persisted for Shield Configuration extension

Issues / limitations:
- Only enforceable scheduled modes are persisted in native schedule store; full user mode catalog is not stored by plugin (host app must persist full catalog).
- iOS reliable pause auto-resume requires host Device Activity Monitor extension integration.

Fixability:
- Persist-only-enforceable behavior: Intentional design; fixable if product decides plugin should own full mode catalog.
- iOS extension dependency for reliability: Not fully fixable inside plugin; host integration requirement.

---

### 1.7 Schedule and conflict resolution

Implemented:
- Schedule data model with weekly days + start/end minutes.
- Overlap detection on mode upsert (Android and iOS) and in Dart model validation.
- Runtime resolution logic:
  - If manual mode exists -> manual wins.
  - Else if exactly one scheduled mode active now -> scheduled mode applies.
  - Else -> no active scheduled enforcement.

Implementation details:
- Both Android and iOS resolvers reject ambiguous active-schedule states by returning no active scheduled mode.
- Cross-midnight schedules supported.

Issues / limitations:
- iOS schedule monitors are time-interval-based and do not encode weekday constraints directly in monitor registration. Correct day filtering is deferred to runtime session resolution logic (works functionally but can create extra monitor wakeups).

Fixability:
- Extra wakeup behavior is partly platform-model constrained; optimization is possible but not a full semantic blocker.

---

## 2) Per-core-feature problems, limitations, and fixability

### Feature: Reliable Manual Mode

Current status:
- Implemented on Android and iOS.
- Manual active mode is persisted and survives app restarts/reboots.
- Manual mode precedence over scheduled mode is implemented.

Problems / limitations:
- `startModeSession(modeId)` for unscheduled modes depends on in-memory upsert cache in the same app run unless mode is persisted as scheduled mode.
- If runtime prerequisites are missing (Android accessibility / iOS authorization), manual start may succeed as an API call but enforcement is not active.

Fixability:
- Cache dependency nuance: Fixable (persist richer mode metadata or provide stronger contract checks).
- Missing-prerequisite silent non-enforcement: Fixable.

---

### Feature: Reliable-Enforced Pause

Current status:
- Implemented on both platforms.
- Pause state persisted.
- Resume can be automatic via alarm/monitor and manual via API.

Problems / limitations:
- Android pause-end exactness can degrade without exact alarm permission (falls back to inexact scheduling).
- iOS enforces max pause duration <24h (hard guard).
- iOS reliable background auto-resume depends on host Device Activity Monitor extension setup.

Fixability:
- Android exactness without exact alarms: Not fully fixable (OS behavior).
- iOS <24h cap: Fixable from code perspective, but likely intentional reliability guard.
- Extension dependency: Not fixable within plugin alone.

---

### Feature: Reliable Schedules

Current status:
- Implemented with persistence and automatic boundary orchestration on both platforms.
- Reboot/time-change handling exists (Android receiver + startup rescheduling; iOS monitor rescheduling).

Problems / limitations:
- iOS schedule monitor registration itself does not encode weekdays; day-of-week correctness relies on resolver checks at runtime.
- Startup iOS monitor reschedule errors are silently ignored at registration time (`try?`), reducing observability.

Fixability:
- Weekday handling optimization: Partially fixable (depends on DeviceActivity monitor model).
- Silent startup error handling: Fixable.

---

### Feature: Shield Configuration

Current status:
- Implemented on Android and iOS with title/subtitle/colors/blur/icon/button labels.
- iOS supports App Group-backed configuration for shield extension.

Problems / limitations:
- iOS custom shield requires host Shield Configuration extension to consume stored config.
- Without valid App Group setup, configuration operations can fail (typed `INTERNAL_FAILURE`).

Fixability:
- Extension dependency: Not fixable in plugin-only code.
- App Group error ergonomics/docs: Fixable and already partially addressed.

---

### Feature: App Usage Statistics

Current status:
- Android data retrieval implemented.
- iOS UI report embedding implemented.

Problems / limitations:
- iOS raw usage data retrieval unavailable.
- Android outputs depend on system usage stats availability/OEM behavior.

Fixability:
- iOS raw data: Not fixable (platform policy).
- Android variability: Not fully fixable.

---

### Feature: Applications Enumeration

Current status:
- Android enumeration implemented.
- iOS picker-token selection implemented.

Problems / limitations:
- iOS full enumeration not possible.
- Android full enumeration may be policy-restricted by Play requirements.

Fixability:
- iOS enumeration: Not fixable.
- Android policy constraints: Partially fixable via narrower product scope.

---

### Feature: Permissions

Current status:
- Implemented across Android and iOS with checks + request flows.

Problems / limitations:
- Some permission failures are collapsed into simple false/unknown outcomes instead of rich typed propagation.

Fixability:
- Fixable.

---

### Feature: Prioritization & Conflict Resolution

Current status:
- Implemented:
  - Single active mode semantics at runtime.
  - Overlap rejection for schedules.
  - Manual override precedence over schedules.

Problems / limitations:
- When overlap slips in through corrupted storage or unexpected state, resolver chooses safe fallback (no scheduled mode), which is conservative but can surprise integrators.

Fixability:
- Fixable (e.g., stricter storage recovery + diagnostics), but current behavior is intentionally safe.

---

## 3) Notable cross-cutting gaps

### 3.1 Honest fast-failure is inconsistent

Observed:
- Strong typed failure exists in many paths.
- But several flows still degrade to silent fallback booleans / no-op outcomes.

Impact:
- Host app may think operation succeeded while enforcement is not actually possible.

Fixability:
- Fixable.

### 3.2 Runtime prerequisite enforcement feedback is weak in some restrictions flows

Observed:
- Restriction operations can return success even when required permission/authorization is absent, while runtime enforcement remains inactive.

Impact:
- Possible mismatch between app UX state and actual shield behavior.

Fixability:
- Fixable.

### 3.3 Plugin intentionally does not persist full mode catalog

Observed:
- Only enforceable scheduled modes are persisted in native schedule stores.

Impact:
- Host app must maintain authoritative catalog itself.

Fixability:
- Fixable by design change, but current behavior is explicit and documented.

---

## 4) Adherence to `specs/technical_requirements.md`

### 4.1 Strong Typization

Verdict: **Partially adherent (strong overall, with channel-bound dynamic edges)**

Why:
- Good typed models across Dart/Kotlin/Swift for core entities.
- Sealed/enum-based modeling is used in key places.
- However, method-channel boundaries still rely on map/dynamic payload parsing (expected in Flutter channels), and strictness varies by path.

### 4.2 Honest Fast-Failure

Verdict: **Partially adherent**

Why:
- Typed taxonomy and propagation are implemented for many operations.
- But there are documented silent fallback paths and dropped startup errors, which violate strict "fail loudly" intent.

### 4.3 No God Class

Verdict: **Adherent**

Why:
- Codebase is split by feature and responsibility (handlers, stores, managers, resolvers, schedulers, models).
- No dominant cross-domain god object detected.

### 4.4 Documented

Verdict: **Adherent with minor caveats**

Why:
- Docs are extensive (setup, features, errors, troubleshooting, templates).
- Important assumptions/limitations are documented, especially iOS extension dependencies.
- Minor caveat: some implementation-specific fallbacks are not prominently documented as behavior contracts.

Overall technical requirements adherence: **Partially adherent (3/4 strongly met; fast-failure consistency remains primary gap).**

---

## 5) Adherence to `specs/specifications.md`

### 5.1 Reliable Manual Mode

Verdict: **Mostly adherent**

Notes:
- Start/end, override, and persistence behaviors are implemented.
- Enforcement still depends on prerequisites; missing prerequisites can create apparent-start without effective shielding.

### 5.2 Reliable-Enforced Pause

Verdict: **Partially adherent**

Notes:
- Implemented with persistence and boundary callbacks.
- Reliability on iOS requires monitor extension; Android exactness can degrade without exact alarms.

### 5.3 Reliable Schedules

Verdict: **Mostly adherent**

Notes:
- Persistence and background boundary orchestration exist on both platforms.
- iOS monitor strategy introduces extra callbacks but final enforcement state is resolver-driven.

### 5.4 Shield Configuration

Verdict: **Adherent**

### 5.5 App Usage Statistics

Verdict: **Partially adherent (cross-platform asymmetry)**

Notes:
- Android data API implemented.
- iOS provides UI report only, not raw data, due platform limits.

### 5.6 Applications Enumeration

Verdict: **Partially adherent (platform-limited on iOS)**

Notes:
- Android full enumeration implemented.
- iOS token-based picker only, per platform constraints.

### 5.7 Permissions

Verdict: **Adherent (with diagnostic-quality caveats)**

### 5.8 Prioritization & Conflict Resolution

Verdict: **Adherent**

Notes:
- Single active mode semantics + overlap prevention + manual override are implemented.

Overall spec adherence: **Partially adherent**.

Primary blockers to full adherence are platform constraints (iOS enumeration + raw usage data), plus a few fixable behavior/diagnostic gaps (fast-failure consistency and prerequisite feedback strictness).
