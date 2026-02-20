# Current State of Pauza Screen Time Codebase

This document outlines the current state of the `pauza_screen_time` Flutter plugin codebase. It identifies potential bugs, code simplification and refactoring opportunities, and other architectural issues, specifically focusing on the recent team goals: strong typization, honest fast-failure, avoiding God Classes, and general code health.

## 1. Potential Bugs

### 1.1 Android `RestrictionManager.kt` Performance Issue (O(N^2) Deletion)
In `RestrictionManager.kt`, the `appendLifecycleEvents` function enforces a maximum event limit (`MAX_LIFECYCLE_EVENTS = 10_000`) using the following logic:
```kotlin
if (persisted.size > MAX_LIFECYCLE_EVENTS) {
    val overflow = persisted.size - MAX_LIFECYCLE_EVENTS
    repeat(overflow) { persisted.removeAt(0) }
}
```
`persisted` is an `ArrayList` (created via `toMutableList()`). Removing the first element from an `ArrayList` requires shifting all subsequent elements, which operates in `O(N)` time. Doing this in a `repeat` loop results in `O(N * overflow)` performance. This can cause severe UI stuttering and potential ANRs when the event queue becomes full on the main thread.
**Fix**: Use `drop(overflow).toMutableList()` or a more efficient queue/circular buffer data structure.

### 1.2 Synchronous Main-Thread I/O in Android
`RestrictionManager.kt` performs synchronous SharedPreferences reads and writes (e.g., parsing `JSONObject` from strings) heavily within `synchronized(this)` blocks. Since Flutter method channel calls often execute on the primary platform thread (Main Thread), this synchronous disk I/O risks triggering StrictMode violations and App Not Responding (ANR) warnings.
**Fix**: Migrate these operations to asynchronous background threads or use an async-first storage abstraction like DataStore.

### 1.3 UI State Mutation Inside Query Methods in iOS 
In iOS `RestrictionsMethodHandler.swift`, query methods like `handleIsRestrictionSessionActiveNow` and `handleGetRestrictionSession` call `applyDesiredRestrictionsIfNeeded(...)`. This function resolves state, interacts with `ShieldManager.shared` (mutating the UI constraints) and appends lifecycle transitions to the store (`_ = RestrictionStateStore.appendLifecycleTransition(...)`).
**Fix**: Enforce Command-Query Separation (CQS). Queries should only read data without producing side-effects like mutating state or recording lifecycle events.

### 1.4 Silent Failures in iOS `ShieldManager.swift`
The `ShieldManager.swift` implements `addRestrictedApp`, `removeRestrictedApp`, and `isRestricted` by silently returning `nil` if the token cannot be decoded. This contradicts the "Honest fast-failure" principle.
```swift
guard let token = decodeToken(base64Token) else { return nil }
```
**Fix**: If a token string is invalid, the operation should explicitly throw an error so the caller (and the Dart side) is immediately aware that an invalid constraint form was provided.

## 2. Potential Code Simplification & Refactoring

### 2.1 "God Classes" and Responsibility Bloat
Several classes have amassed overwhelming responsibilities, becoming "God Classes" that are difficult to safely test and modify:
- **`RestrictionManager.kt` (Android):** This class (nearly 500 lines) handles SharedPreferences operations, raw JSON serialization/deserialization, complex business logic for modes and pauses, unique session ID sequence generation, and lifecycle event appending. It should be refactored into:
  - `RestrictionStorageRepository` layer that hides SharedPreferences logic.
  - `RestrictionLifecycleLogger` specifically for managing event queues.
  - Separate Kotlin models that know how to serialize themselves via `kotlinx.serialization` instead of manual `JSONObject` building.
- **`RestrictionsMethodHandler.swift` (iOS) & `RestrictionsMethodHandler.kt` (Android):** Both channel handlers are excessively large (900 lines and ~800 lines respectively). They contain deep validation logic and state orchestration instead of merely parsing channel arguments and dispatching to use cases.

### 2.2 Manual JSON Parsing in Kotlin & Swift
The Kotlin Android codebase does extensive manual JSON parsing:
```kotlin
val blocked = payload.optJSONArray(KEY_ACTIVE_SESSION_BLOCKED_APPS)
// loops to manually append strings
val modeId = payload.optString(KEY_ACTIVE_SESSION_MODE_ID, "").trim()
```
The iOS Swift codebase manually decodes objects and converts between base64 representations continuously.
**Fix**: Standardize on a formal serialization library (e.g. `kotlinx.serialization` on Android, standard robust `Codable` on iOS) to replace ad-hoc `optString` calls. This eliminates parsing edge-case bugs and aligns with "strong typization" policies.

## 3. Typization and Channel Boundaries

### 3.1 Unsafe Method Channel Payloads
Currently, the method channels rely on raw `Map<String, Any?>` to transport data between Dart and the host platforms. This requires exhaustive and error-prone defensive parsing on both ends:
```kotlin
val blockedAppIdsRaw = payload["blockedAppIds"] as? List<*>
val modeId = (payload["modeId"] as? String)?.trim().orEmpty()
```
The codebase lacks a strong typing bridge. 
**Recommendation**: The team goal is "Aligning Codebase Typization... ensuring type safety across the application and at method channel boundaries." To achieve this correctly, integrate **Pigeon**, which auto-generates type-safe Data Transfer Objects (DTOs) and channel bindings for Dart, Kotlin, and Swift.

### 3.2 Constants and Magic Numbers
Various operational constants are scattered and hardcoded within logic blocks, requiring defensive duplication:
- `MAX_LIFECYCLE_EVENTS = 10_000` (Kotlin)
- `200` for default limits.
- `24 * 60 * 60 * 1000L` for maximum pause durations.
**Recommendation**: Relocate these into shared constants files (e.g. `PlatformConstants.kt`, `PlatformConstants.swift`) and define a single source of truth—possibly driven by Dart channel configurations—for thresholds.

## 4. Summary

Although the project correctly leverages native scheduling and restriction APIs in Android (`AlarmManager`) and iOS (`FamilyControls`), its structural stability is hindered by overloaded architecture components and un-typed boundaries:
1. Standardize and automate Serialization.
2. Adopt Pigeon for strong typization at the boundary.
3. Break down the respective managers and handlers into cleanly decoupled domain-specific repositories.
4. Correct the `O(N^2)` bugs to protect the native host's Main Thread.
