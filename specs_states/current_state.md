# Current State of Pauza Screen Time Codebase

This document outlines the current state of the `pauza_screen_time` Flutter plugin codebase. It identifies potential bugs, code simplification and refactoring opportunities, and other architectural issues, specifically focusing on the recent team goals: strong typization, honest fast-failure, avoiding God Classes, and general code health.

## 1. Potential Bugs

### 1.1 [RESOLVED] Android `RestrictionManager.kt` Performance Issue (O(N^2) Deletion)
In `RestrictionManager.kt`, the `appendLifecycleEvents` function previously enforced a maximum event limit using an `O(N^2)` `removeAt(0)` loop within an `ArrayList`.
**Fix Implemented**: The event persistence logic was delegated to `RestrictionLifecycleLogger`, which now efficiently uses `.drop()` to safely slice the collection when enforcing the `MAX_LIFECYCLE_EVENTS` limit.

### 1.2 Synchronous Main-Thread I/O in Android
`RestrictionManager.kt` performs synchronous SharedPreferences reads and writes (e.g., parsing `JSONObject` from strings) heavily within `synchronized(this)` blocks. Since Flutter method channel calls often execute on the primary platform thread (Main Thread), this synchronous disk I/O risks triggering StrictMode violations and App Not Responding (ANR) warnings.
**Fix**: Migrate these operations to asynchronous background threads or use an async-first storage abstraction like DataStore.

### 1.3 [RESOLVED] UI State Mutation Inside Query Methods in iOS 
In iOS `RestrictionsMethodHandler.swift`, query methods like `handleIsRestrictionSessionActiveNow` previously called mutating functions such as `applyDesiredRestrictionsIfNeeded(...)` that altered UI restrictions and wrote lifecycle events.
**Fix Implemented**: Command-Query Separation (CQS) is now rigidly enforced via `SessionEnforcementUseCase`. Queries purely read and evaluate the current state without triggering any side-effects.

### 1.4 Silent Failures in iOS `ShieldManager.swift`
The `ShieldManager.swift` implements `addRestrictedApp`, `removeRestrictedApp`, and `isRestricted` by silently returning `nil` if the token cannot be decoded. This contradicts the "Honest fast-failure" principle.
```swift
guard let token = decodeToken(base64Token) else { return nil }
```
**Fix**: If a token string is invalid, the operation should explicitly throw an error so the caller (and the Dart side) is immediately aware that an invalid constraint form was provided.

## 2. Potential Code Simplification & Refactoring

### 2.1 [RESOLVED] "God Classes" and Responsibility Bloat
Several classes previously amassed overwhelming responsibilities, becoming "God Classes". This has been fully refactored:
- **`RestrictionManager.kt` (Android):** Now acts solely as a facade. Its responsibilities are cleanly decoupled into a `RestrictionStorageRepository` (abstracting SharedPreferences) and `RestrictionLifecycleLogger` (managing event queues).
- **`RestrictionsMethodHandler` (Android & iOS):** Both handlers were stripped of deep business validation and state orchestration. They now simply decode method channel arguments and dispatch execution to single-responsibility Use Cases (e.g., `ConfigureShieldUseCase`, `ManageModesUseCase`, `SessionEnforcementUseCase`, `LifecycleEventsUseCase`).

### 2.2 [RESOLVED] Manual JSON Parsing in Kotlin & Swift
The Kotlin Android codebase previously did extensive manual JSON parsing via `optString` and `optJSONArray`.
**Fix Implemented**: The Android layer was modernized to use `kotlinx.serialization`. Models like `ActiveSession`, `RestrictionLifecycleEvent`, and `ShieldConfig` are now auto-serialized with `@Serializable`. (iOS still requires a future pass to fully unify data persistence models with `Codable`).

## 3. Typization and Channel Boundaries

### 3.1 Unsafe Method Channel Payloads
Currently, the method channels rely on raw `Map<String, Any?>` to transport data between Dart and the host platforms. This requires exhaustive and error-prone defensive parsing on both ends:
```kotlin
val blockedAppIdsRaw = payload["blockedAppIds"] as? List<*>
val modeId = (payload["modeId"] as? String)?.trim().orEmpty()
```
The codebase lacks a strong typing bridge. 
**Recommendation**: The team goal is "Aligning Codebase Typization... ensuring type safety across the application and at method channel boundaries." To achieve this correctly, integrate **Pigeon**, which auto-generates type-safe Data Transfer Objects (DTOs) and channel bindings for Dart, Kotlin, and Swift.

### 3.2 [RESOLVED] Constants and Magic Numbers
Various operational constants were scattered and hardcoded within logic blocks, requiring defensive duplication:
- `MAX_LIFECYCLE_EVENTS = 10_000` (Kotlin)
- `200` for default limits.
- `24 * 60 * 60 * 1000L` for maximum pause durations.
**Fix Implemented**: Removed all local hardcoded usages. Relocated these into shared constants files (`PlatformConstants.dart`, `PlatformConstants.kt`, `PlatformConstants.swift`) to enforce a single source of truth across all platforms.

## 4. Summary

Although the project correctly leverages native scheduling and restriction APIs in Android (`AlarmManager`) and iOS (`FamilyControls`), its structural stability was historically hindered by overloaded architecture components and un-typed boundaries:
1. Standardize and automate Serialization. **(Partially completed: `kotlinx.serialization` on Android is complete).**
2. Adopt Pigeon for strong typization at the boundary.
3. Break down the respective managers and handlers into cleanly decoupled domain-specific repositories. **(Completed: Method channel handlers now delegate to specific Use Cases and Repositories).**
4. Correct the `O(N^2)` bugs to protect the native host's Main Thread. **(Completed).**
