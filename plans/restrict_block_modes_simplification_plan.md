## Restrict/Block Modes Simplification + Android `<24h` Pause Guard

### Summary
- Align plugin behavior with a strict contract: plugin persists only enforceable scheduled modes and current manual active mode.
- Remove confusing/unused configuration API surface (`isRestrictionSessionConfigured`) entirely.
- Make “disabled schedule” impossible inside plugin by removing mode-level `isEnabled` from API/model; host app controls disabling by removing schedule-backed modes from plugin persistence.
- Add Android pause-duration reliability guard to match iOS rule: pause must be strictly `<24h`.

### Public API / Interface Changes (Breaking)
- Remove `isEnabled` from Dart `RestrictionMode`.
  - Update `/Users/alisher/flutter_projects/pauza_screen_time/lib/src/features/restrict_apps/model/restriction_mode.dart`.
  - Remove `isEnabled` from `toMap`/`fromMap` payload.
- Remove `isRestrictionSessionConfigured()` from all layers.
  - Dart platform contract: `/Users/alisher/flutter_projects/pauza_screen_time/lib/src/features/restrict_apps/app_restriction_platform.dart`.
  - Manager: `/Users/alisher/flutter_projects/pauza_screen_time/lib/src/features/restrict_apps/data/app_restriction_manager.dart`.
  - Method channel names/invocation: `/Users/alisher/flutter_projects/pauza_screen_time/lib/src/features/restrict_apps/method_channel/method_names.dart`, `/Users/alisher/flutter_projects/pauza_screen_time/lib/src/features/restrict_apps/method_channel/restrictions_method_channel.dart`.
  - Android/iOS native method name constants and handlers.
- Keep `setModesEnabled(bool)` as global schedule-engine toggle.
- Update semantics: any mode present in plugin scheduled store is enforceable by definition; “disabled” state is represented by absence (`removeMode`).

### Android Implementation Plan
- Files:
  - `/Users/alisher/flutter_projects/pauza_screen_time/android/src/main/kotlin/com/example/pauza_screen_time/app_restriction/method_channel/RestrictionsMethodHandler.kt`
  - `/Users/alisher/flutter_projects/pauza_screen_time/android/src/main/kotlin/com/example/pauza_screen_time/app_restriction/schedule/RestrictionScheduledModeEntry.kt`
  - `/Users/alisher/flutter_projects/pauza_screen_time/android/src/main/kotlin/com/example/pauza_screen_time/app_restriction/schedule/RestrictionScheduledModesStore.kt`
  - `/Users/alisher/flutter_projects/pauza_screen_time/android/src/main/kotlin/com/example/pauza_screen_time/app_restriction/schedule/RestrictionScheduledModeResolver.kt`
  - `/Users/alisher/flutter_projects/pauza_screen_time/android/src/main/kotlin/com/example/pauza_screen_time/core/MethodNames.kt`
- Changes:
  - Remove parsing/usage of mode `isEnabled` from upsert payload.
  - Persist scheduled mode only when `schedule != null` and `blockedAppIds` non-empty; otherwise remove by `modeId`.
  - Remove all `it.isEnabled` filters in schedule resolution/orchestration because persisted entries are already enforceable.
  - Remove `IS_RESTRICTION_SESSION_CONFIGURED` route and handler.
  - Add `maxReliablePauseDurationMs = 24 * 60 * 60 * 1000L` and reject `durationMs >= maxReliablePauseDurationMs` with `INVALID_ARGUMENT`.
  - Add Android-specific clear error message, e.g. “Pause duration must be less than 24 hours on Android”.
  - Update manual session validation messaging to remove “enabled” wording (mode existence + valid blocked apps only).

### iOS Implementation Plan
- Files:
  - `/Users/alisher/flutter_projects/pauza_screen_time/ios/Classes/AppRestriction/RestrictionSchedule.swift`
  - `/Users/alisher/flutter_projects/pauza_screen_time/ios/Classes/AppRestriction/MethodChannel/RestrictionsMethodHandler.swift`
  - `/Users/alisher/flutter_projects/pauza_screen_time/ios/Classes/AppRestriction/RestrictionScheduleMonitorOrchestrator.swift`
  - `/Users/alisher/flutter_projects/pauza_screen_time/ios/Classes/Core/MethodNames.swift`
- Changes:
  - Remove `isEnabled` from `RestrictionScheduledMode` (channel/storage parsing + serialization + startable logic).
  - Keep persistence rule strict: only schedule+blocked-app enforceable entries remain stored.
  - Remove `isRestrictionSessionConfigured` handler/case.
  - Remove `filter { $0.isEnabled }` schedule monitor selection (not needed once model simplified).
  - Keep existing iOS `<24h` guard unchanged.

### Dart Layer and Model Validation Plan
- Files:
  - `/Users/alisher/flutter_projects/pauza_screen_time/lib/src/features/restrict_apps/model/restriction_mode.dart`
  - `/Users/alisher/flutter_projects/pauza_screen_time/lib/src/features/restrict_apps/model/restriction_modes_config.dart`
  - `/Users/alisher/flutter_projects/pauza_screen_time/lib/src/features/restrict_apps/app_restriction_platform.dart`
  - `/Users/alisher/flutter_projects/pauza_screen_time/lib/src/features/restrict_apps/data/app_restriction_manager.dart`
  - `/Users/alisher/flutter_projects/pauza_screen_time/lib/src/features/restrict_apps/method_channel/method_names.dart`
  - `/Users/alisher/flutter_projects/pauza_screen_time/lib/src/features/restrict_apps/method_channel/restrictions_method_channel.dart`
- Changes:
  - Delete `RestrictionMode.isEnabled` field and constructor arg.
  - Update overlap validation in `RestrictionModesConfig.isValid` to include all scheduled modes (no enabled filter).
  - Remove `isRestrictionSessionConfigured` abstract method + manager method + channel method.
  - Ensure method-channel payload contracts match new native fields.

### Docs / Spec Updates
- Files:
  - `/Users/alisher/flutter_projects/pauza_screen_time/specs_states/current_state.md`
  - `/Users/alisher/flutter_projects/pauza_screen_time/docs/restrict-apps.md`
  - `/Users/alisher/flutter_projects/pauza_screen_time/README.md`
  - `/Users/alisher/flutter_projects/pauza_screen_time/CHANGELOG.md`
  - Optional cross-links: `/Users/alisher/flutter_projects/pauza_screen_time/docs/troubleshooting.md`, `/Users/alisher/flutter_projects/pauza_screen_time/docs/android-setup.md`
- Changes:
  - Rewrite section 1.6 language to state explicit persistence contract: enforceable scheduled modes + manual active mode only.
  - Document that disabling/removing schedules is host-owned and represented by deleting mode from plugin storage.
  - Document Android `<24h` pause rule.
  - Remove all references/examples using `isEnabled` and `isRestrictionSessionConfigured`.

### Test Plan
- Dart unit tests:
  - Update `/Users/alisher/flutter_projects/pauza_screen_time/test/restrictions_session_test.dart` for new `RestrictionMode` constructor and removed configured API.
  - Add parse/serialization tests asserting `RestrictionMode` has no `isEnabled`.
  - Add validation test: overlap checks run across all scheduled modes.
- Android tests:
  - Add/extend handler tests for `pauseEnforcement`:
    - `durationMs <= 0` => `INVALID_ARGUMENT`.
    - `durationMs == 24h` => `INVALID_ARGUMENT`.
    - `durationMs > 24h` => `INVALID_ARGUMENT`.
    - `durationMs == 24h - 1ms` => success path.
  - Add test asserting upsert with no schedule removes persisted mode.
- iOS tests (or static validation if no test harness):
  - Validate `RestrictionScheduledMode` decoding without `isEnabled`.
  - Validate monitor rescheduling uses all persisted modes.
- Contract sweep:
  - Ensure no code references removed method names/fields via repo search.

### Acceptance Criteria
- No `isEnabled` in public mode contract or channel payload.
- No `isRestrictionSessionConfigured` in Dart, Android, iOS APIs or docs.
- Persisted scheduled modes are always enforceable entries; disabled state is represented by removal.
- Android rejects pause durations `>=24h` with `INVALID_ARGUMENT`.
- Existing manual-session precedence, schedule overlap validation, and pause/resume behavior remain intact.

### Assumptions and Defaults
- Fresh install only; no migration/legacy compatibility paths will be implemented.
- Breaking changes are allowed and intentional.
- Host app is source of truth for full mode catalog (including disabled/unscheduled states).
- `setModesEnabled` remains as global schedule engine control.
