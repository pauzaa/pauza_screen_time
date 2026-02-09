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
