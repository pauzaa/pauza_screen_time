## 0.6.1

* Added optional `duration` to manual `startSession(...)` so sessions can auto-end after elapsed time.
* `startSession(...)` now rejects with `INVALID_ARGUMENT` when any restriction session is already active.
* Added `< 24h` validation for `startSession` duration on Android/iOS.

## 0.6.0

* Added durable restriction lifecycle queue APIs:
  * `AppRestrictionManager.getPendingLifecycleEvents({int limit = 200})`
  * `AppRestrictionManager.ackLifecycleEvents({required String throughEventId})`
* Added typed Dart lifecycle event model: `RestrictionLifecycleEvent` with
  `id`, `sessionId`, `modeId`, `action`, `source`, `reason`, `occurredAt`.
* Added plugin-level lifecycle transition emission for manual and scheduled
  restriction changes across Android and iOS.
* Delivery semantics: at-least-once with inclusive ack checkpoint and bounded
  native queue pruning policy.
* Additive and backward compatible: existing restriction APIs and behavior
  remain supported.

## 0.5.1

* BREAKING: Removed `RestrictionMode.isEnabled` from Dart and native restriction mode payload contracts.
* BREAKING: Removed `isRestrictionSessionConfigured` from Dart manager/platform and native method channels.
* Restriction mode persistence is now explicit: only enforceable scheduled modes (`schedule != null && blockedAppIds.isNotEmpty`) are stored by native schedule stores.
* Android now rejects `pauseEnforcement` durations `>= 24h` with `INVALID_ARGUMENT` ("Pause duration must be less than 24 hours on Android").

## 0.5.0

* BREAKING: Restriction APIs are now mode-centric. Added `RestrictionMode` and `RestrictionModesConfig`; removed global app-list restriction entry points from manager/channel contracts.
* BREAKING: Manual session APIs changed from `startRestrictionSession`/`endRestrictionSession` to `startModeSession(modeId)`/`endModeSession()`.
* BREAKING: Scheduled mode APIs were replaced with unified mode APIs: `upsertMode`, `removeMode`, `setModesEnabled`, `getModesConfig`.
* Added `RestrictionSession.activeModeId` and `RestrictionSession.activeModeSource` (`none`, `manual`, `schedule`) to expose active mode identity directly.
* Android and iOS runtime resolution now uses a shared active-mode model: manual mode id override first, then scheduled mode resolution.

## 0.4.0

* BREAKING: Removed legacy schedule APIs `setRestrictionScheduleConfig` and `getRestrictionScheduleConfig` from Dart and native method channels.
* BREAKING: Removed legacy schedule persistence/runtime paths; scheduled-mode APIs are now the only supported schedule configuration path.
* iOS schedule monitor orchestration now derives schedules only from scheduled modes, removing legacy fallback logic.

## 0.3.0

* BREAKING: Android usage stats timestamp schema is now explicit:
  * Removed ambiguous `firstUsed` / `lastUsed` fields from `UsageStats`.
  * Renamed bucket timestamps to `bucketStart` / `bucketEnd`.
  * Added `lastTimeUsed` mapped from Android `UsageStats.lastTimeUsed`.
* Android native usage stats payload now emits `bucketStartMs`, `bucketEndMs`, `lastTimeUsedMs`, `lastTimeVisibleMs`.
* `UsageStats.fromMap()` keeps backward compatibility for legacy `firstTimeStampMs` / `lastTimeStampMs` keys during deserialization.

## 0.2.0

* BREAKING: `PermissionManager.requestAndroidPermission()` now returns `Future<void>` and opens Android Settings flows instead of returning a misleading grant boolean.
* BREAKING: `PermissionHelper.requestAllRequiredPermissions()` now returns `Future<void>`.
* Android helper request flow now excludes `AndroidPermission.queryAllPackages` (manifest/policy capability).
* Android helper now opens only the first missing runtime permission settings screen (`usageStats` first, then `accessibility`).

## 0.1.0

* BREAKING: Plugin now emits only taxonomy error codes: `UNSUPPORTED`, `MISSING_PERMISSION`, `PERMISSION_DENIED`, `SYSTEM_RESTRICTED`, `INVALID_ARGUMENT`, `INTERNAL_FAILURE`.
* BREAKING: Legacy feature-specific error codes are removed from plugin emissions.
* BREAKING: Public manager APIs now throw sealed typed `PauzaError` subclasses (instead of exposing raw `PlatformException`).
* Updated error documentation to taxonomy-only contract and typed sealed exception usage.

## 0.0.2

* BREAKING: Restriction APIs now take/return `AppIdentifier` instead of raw `String`.
* BREAKING: Restriction method-channel argument keys are now `identifier` / `identifiers` instead of `packageId` / `packageIds`.

## 0.0.1

* Initial release.
