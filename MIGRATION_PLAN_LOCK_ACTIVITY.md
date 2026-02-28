# Migration Plan: Accessibility Overlay to LockActivity Shield Screen

## 1. Architecture Overview

### Current Flow
```
AccessibilityEvent -> AppMonitoringService -> ShieldOverlayManager.showShield()
                                               -> WindowManager.addView(TYPE_ACCESSIBILITY_OVERLAY)
```

### Target Flow
```
AccessibilityEvent -> AppMonitoringService -> performGlobalAction(GLOBAL_ACTION_HOME)
                                           -> launchLockActivity(packageId)
                                               -> LockActivity (fullscreen, excludeFromRecents)
```

---

## 2. Component Inventory: What Changes, What Stays

| Component | Action | Notes |
|---|---|---|
| `AppMonitoringService` | **Modify** | Replace `ShieldOverlayManager.showShield()` with HOME + LockActivity launch. Add lock-visible guard, fallback logic. |
| `ShieldOverlayManager` | **Remove** (or retain as dead code for rollback) | Entire class replaced by `LockActivity`. |
| `ShieldOverlayContent.kt` | **Retain/Migrate** | Compose UI reused inside `LockActivity.setContent{}`. |
| `OverlayViewTreeOwners.kt` | **Remove** | No longer needed; Activity provides its own lifecycle. |
| `LockActivity` | **New file** | `app_restriction/LockActivity.kt` |
| `LockVisibilityState` | **New file** | `app_restriction/LockVisibilityState.kt` -- shared atomic flag. |
| `ConfigureShieldUseCase` | **Modify** | Persist config to `ShieldConfigStore` (extracted from `ShieldOverlayManager`) instead of overlay manager. |
| `ShieldConfigStore` | **New file** | `app_restriction/storage/ShieldConfigStore.kt` -- extracts config persistence from `ShieldOverlayManager`. |
| `RestrictionSessionController` | **Modify** | Replace `ShieldOverlayManager.getInstanceOrNull()?.hideShield()` calls with `LockVisibilityState.requestDismiss()` + finish broadcast/intent. |
| `SessionEnforcementUseCase` | **Modify** | Same: replace `ShieldOverlayManager` references with LockActivity dismiss mechanism. |
| `RestrictionManager` | **No change** | |
| `RestrictionsMethodHandler` | **No change** | (ConfigureShieldUseCase change is transparent) |
| `AndroidManifest.xml` | **Modify** | Add `LockActivity` declaration. |
| `accessibility_service_config.xml` | **No change** | Already has required event types set in code via `configureServiceMonitoring`. |

---

## 3. New and Modified Files

### 3.1 New: `LockActivity.kt`

**File**: `android/src/main/kotlin/com/example/pauza_screen_time/app_restriction/LockActivity.kt`

**Responsibilities**:
- Fullscreen Compose-based activity showing the shield UI.
- Reads `ShieldConfig` from persisted store and `blockedPackageId` from intent extras.
- Intercepts back press to prevent dismissal.
- Sets `LockVisibilityState.isLockVisible = true` in `onCreate`/`onResume`, clears in `onDestroy`.
- On button tap: calls HOME intent + `finish()`.
- Listens for a "dismiss" broadcast/flag so session-end can force-close it.

**Launch mode justification**: Use `singleInstance` with `android:taskAffinity` set to a unique value (e.g., `":lockTask"`). Rationale:
- `singleTask` reuses the existing task, which in a Flutter plugin means the Flutter activity's task. This would bring our Flutter app to foreground, which is wrong.
- `singleInstance` gets its own task, so it floats independently. Combined with `excludeFromRecents="true"`, it won't appear in recents.
- Alternative: `singleTop` with `FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_CLEAR_TOP` could also work but `singleInstance` is more predictable for a lock screen use case.

> **Decision point**: `singleInstance` is recommended. If testing reveals OEM issues with `singleInstance` + accessibility service context, fall back to `singleTop` with explicit task affinity.

### 3.2 New: `LockVisibilityState.kt`

**File**: `android/src/main/kotlin/com/example/pauza_screen_time/app_restriction/LockVisibilityState.kt`

**Responsibilities**:
- Singleton object with `@Volatile var isLockVisible: Boolean`.
- `var currentBlockedPackage: String?` -- tracks what package the lock is shown for.
- `var lastLockLaunchTimestamp: Long` -- for throttling.
- Methods: `markVisible(packageId)`, `markHidden()`, `shouldSuppressLaunch(packageId, now)`.

### 3.3 New: `ShieldConfigStore.kt`

**File**: `android/src/main/kotlin/com/example/pauza_screen_time/app_restriction/storage/ShieldConfigStore.kt`

Extract the `persistConfig` / `loadPersistedConfig` / `configure` logic from `ShieldOverlayManager` into this standalone class. Both `LockActivity` and `ConfigureShieldUseCase` reference it.

### 3.4 Modified: `AppMonitoringService.kt`

Key changes to `handleRestrictedAppDetected` and `evaluateForegroundPackage`.

### 3.5 Modified: `AndroidManifest.xml`

Add `LockActivity` declaration.

### 3.6 Modified: `ConfigureShieldUseCase.kt`

Point to `ShieldConfigStore` instead of `ShieldOverlayManager`.

### 3.7 Modified: `RestrictionSessionController.applyCurrentEnforcementState`

Replace `ShieldOverlayManager.getInstanceOrNull()?.hideShield()` with `LockVisibilityState.requestDismiss()` and send a finish broadcast/intent to `LockActivity`.

### 3.8 Modified: `SessionEnforcementUseCase.pauseEnforcement`

Same: replace `ShieldOverlayManager.getInstanceOrNull()?.hideShield()`.

---

## 4. Manifest + Config Snippets

### 4.1 `AndroidManifest.xml` -- Add LockActivity

```xml
<activity
    android:name=".app_restriction.LockActivity"
    android:exported="false"
    android:excludeFromRecents="true"
    android:launchMode="singleInstance"
    android:taskAffinity=":pauza_lock"
    android:theme="@style/Theme.PauzaLock"
    android:configChanges="orientation|screenSize|screenLayout|keyboardHidden"
    android:screenOrientation="unspecified"
    android:noHistory="false" />
```

**Notes**:
- `excludeFromRecents="true"` -- hides from recents carousel.
- `taskAffinity=":pauza_lock"` -- dedicated task so it doesn't merge with the host Flutter app's task.
- `configChanges` -- avoids recreation on rotation (Compose handles it).
- `noHistory="false"` -- we manage lifecycle explicitly; `noHistory=true` would auto-finish on leave which could cause flicker loops.

### 4.2 Theme (add to `res/values/styles.xml` or `themes.xml`)

```xml
<style name="Theme.PauzaLock" parent="Theme.MaterialComponents.NoActionBar">
    <item name="android:windowFullscreen">true</item>
    <item name="android:windowNoTitle">true</item>
    <item name="android:windowBackground">@android:color/black</item>
    <item name="android:statusBarColor">@android:color/transparent</item>
    <item name="android:navigationBarColor">@android:color/transparent</item>
</style>
```

### 4.3 `accessibility_service_config.xml` -- No changes needed

The XML declares `typeWindowStateChanged`. The service code already dynamically sets both `TYPE_WINDOW_STATE_CHANGED | TYPE_WINDOWS_CHANGED` via `configureServiceMonitoring`. This is sufficient.

---

## 5. Pseudocode

### 5.1 `AppMonitoringService` -- Modified Event Handler

```kotlin
// --- New constants ---
companion object {
    private const val LOCK_LAUNCH_THROTTLE_MS = 800L
    // ... existing constants ...
}

// --- Replace handleRestrictedAppDetected ---
private fun handleRestrictedAppDetected(packageName: String) {
    Log.d(TAG, "Restricted app detected: $packageName")

    // Guard: lock already visible for this package
    if (LockVisibilityState.isLockVisible &&
        LockVisibilityState.currentBlockedPackage == packageName) {
        Log.d(TAG, "Lock already visible for $packageName; skipping")
        return
    }

    // Guard: throttle rapid launches
    val now = System.currentTimeMillis()
    if (LockVisibilityState.shouldSuppressLaunch(packageName, now, LOCK_LAUNCH_THROTTLE_MS)) {
        Log.d(TAG, "Lock launch throttled for $packageName")
        return
    }

    // Step 1: Send user HOME
    val homeSuccess = performGlobalAction(GLOBAL_ACTION_HOME)
    Log.d(TAG, "GLOBAL_ACTION_HOME result=$homeSuccess")

    // Step 2: Launch LockActivity immediately (don't wait for HOME)
    launchLockActivity(packageName)

    // Step 3: Fallback BACK action if HOME failed
    if (!homeSuccess) {
        performGlobalAction(GLOBAL_ACTION_BACK)
    }
}

private fun launchLockActivity(packageId: String) {
    val intent = Intent(applicationContext, LockActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_NO_ANIMATION
        putExtra(LockActivity.EXTRA_BLOCKED_PACKAGE, packageId)
    }
    try {
        applicationContext.startActivity(intent)
        LockVisibilityState.markLaunched(packageId)
        Log.d(TAG, "LockActivity launched for $packageId")
    } catch (e: Exception) {
        Log.e(TAG, "Failed to launch LockActivity", e)
        // Ultimate fallback: try BACK to at least leave the blocked app
        performGlobalAction(GLOBAL_ACTION_BACK)
    }
}
```

### 5.2 Modified `evaluateForegroundPackage`

```kotlin
private fun evaluateForegroundPackage(packageName: String, trigger: String) {
    lastForegroundPackage = packageName
    Log.d(TAG, "Evaluating foreground package=$packageName trigger=$trigger")

    // Self-detection guard: skip our own package AND LockActivity
    if (packageName == applicationContext.packageName) {
        // Our app (Flutter host or LockActivity) is foreground -- no action
        return
    }

    if (isLauncherPackage(packageName)) {
        // User is on home screen -- dismiss lock if visible
        dismissLockIfVisible()
        return
    }

    if (isSystemUiOrImePackage(packageName)) return

    // If lock is visible for a different package, dismiss it first
    if (LockVisibilityState.isLockVisible) {
        val blocked = LockVisibilityState.currentBlockedPackage
        if (blocked != null && blocked != packageName) {
            dismissLockIfVisible()
        }
    }

    val restrictionManager = RestrictionManager.getInstance(applicationContext)
    if (restrictionManager.isPausedNow()) {
        dismissLockIfVisible()
        return
    }

    val sessionState = RestrictionSessionController(applicationContext).resolveSessionState()
    restrictionManager.setRestrictedApps(sessionState.blockedAppIds)
    val shouldEnforce = RestrictionSessionController.shouldEnforceNow(
        state = sessionState,
        isPausedNow = false,
    )
    if (!shouldEnforce) {
        dismissLockIfVisible()
        return
    }

    if (isAppRestricted(packageName)) {
        handleRestrictedAppDetected(packageName)
    }
}

private fun dismissLockIfVisible() {
    if (LockVisibilityState.isLockVisible) {
        val intent = Intent(LockActivity.ACTION_DISMISS).apply {
            setPackage(applicationContext.packageName)
        }
        applicationContext.sendBroadcast(intent)
    }
}
```

### 5.3 `LockVisibilityState` Object

```kotlin
object LockVisibilityState {
    @Volatile var isLockVisible: Boolean = false
        private set
    @Volatile var currentBlockedPackage: String? = null
        private set
    @Volatile private var lastLaunchTimestamp: Long = 0L

    fun markVisible(packageId: String) {
        isLockVisible = true
        currentBlockedPackage = packageId
    }

    fun markHidden() {
        isLockVisible = false
        currentBlockedPackage = null
    }

    fun markLaunched(packageId: String) {
        lastLaunchTimestamp = System.currentTimeMillis()
        currentBlockedPackage = packageId
    }

    fun shouldSuppressLaunch(packageId: String, now: Long, throttleMs: Long): Boolean {
        if (isLockVisible && currentBlockedPackage == packageId) return true
        if (now - lastLaunchTimestamp < throttleMs) return true
        return false
    }
}
```

### 5.4 `LockActivity` Pseudocode

```kotlin
class LockActivity : ComponentActivity() {

    companion object {
        const val EXTRA_BLOCKED_PACKAGE = "blocked_package_id"
        const val ACTION_DISMISS = "com.example.pauza_screen_time.DISMISS_LOCK"
    }

    private var blockedPackageId: String? = null

    private val dismissReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            finishAndGoHome()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Make fullscreen / edge-to-edge
        WindowCompat.setDecorFitsSystemWindows(window, false)
        enableEdgeToEdge()

        blockedPackageId = intent?.getStringExtra(EXTRA_BLOCKED_PACKAGE)
        LockVisibilityState.markVisible(blockedPackageId ?: "")

        val config = ShieldConfigStore.getInstance(applicationContext).loadConfig()
            ?: ShieldConfig.DEFAULT

        setContent {
            ShieldOverlayContent(
                config = config,
                onPrimaryClick = { finishAndGoHome() },
                onSecondaryClick = { finishAndGoHome() },
            )
        }

        // Register dismiss receiver
        val filter = IntentFilter(ACTION_DISMISS)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(dismissReceiver, filter, RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(dismissReceiver, filter)
        }

        // Intercept back
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() {
                // No-op: block back press
            }
        })
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Update blocked package if re-launched for a different app
        val newPackageId = intent.getStringExtra(EXTRA_BLOCKED_PACKAGE)
        if (newPackageId != null && newPackageId != blockedPackageId) {
            blockedPackageId = newPackageId
            LockVisibilityState.markVisible(newPackageId)
            // Recomposition will pick up new state if needed
        }
    }

    override fun onResume() {
        super.onResume()
        LockVisibilityState.markVisible(blockedPackageId ?: "")
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(dismissReceiver) } catch (_: Exception) {}
        LockVisibilityState.markHidden()
    }

    private fun finishAndGoHome() {
        LockVisibilityState.markHidden()
        // Navigate to home first, then finish
        val homeIntent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_HOME)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK
        }
        startActivity(homeIntent)
        finish()
    }
}
```

### 5.5 Lock Dismiss from Session Controller

In `RestrictionSessionController.applyCurrentEnforcementState`, replace:
```kotlin
// OLD:
ShieldOverlayManager.getInstanceOrNull()?.hideShield()
// NEW:
if (LockVisibilityState.isLockVisible) {
    val intent = Intent(LockActivity.ACTION_DISMISS).apply {
        setPackage(appContext.packageName)
    }
    appContext.sendBroadcast(intent)
}
```

Same replacement in `SessionEnforcementUseCase.pauseEnforcement` and `AppMonitoringService.onInterrupt`/`onDestroy`.

---

## 6. Sequence Diagrams

### 6.1 Blocked App Detection Path

```
User taps blocked app
  │
  ▼
Android system brings blocked app to foreground
  │
  ▼
AccessibilityService receives TYPE_WINDOW_STATE_CHANGED
  │
  ▼
onAccessibilityEvent()
  ├── event == null || !isMonitoring? → return
  ├── debounce check (500ms) → return if too soon
  ├── same package as last? → return
  │
  ▼
evaluateForegroundPackage(packageName)
  ├── packageName == own package? → return (self-guard)
  ├── isLauncherPackage? → dismissLockIfVisible(); return
  ├── isSystemUiOrImePackage? → return
  ├── isPausedNow? → dismissLockIfVisible(); return
  ├── resolveSessionState() → shouldEnforce? if no → dismissLockIfVisible(); return
  ├── isAppRestricted(packageName)? if no → return
  │
  ▼
handleRestrictedAppDetected(packageName)
  ├── LockVisibilityState: already visible for same pkg? → return
  ├── throttle check (800ms) → return if too soon
  │
  ▼
  ├── 1) performGlobalAction(GLOBAL_ACTION_HOME)
  ├── 2) launchLockActivity(packageId) → startActivity(LockActivity intent)
  └── 3) if HOME failed → performGlobalAction(GLOBAL_ACTION_BACK)
```

### 6.2 Repeated Event Suppression Path

```
Rapid TYPE_WINDOW_STATE_CHANGED events (event storm)
  │
  ▼
onAccessibilityEvent()
  │
  ├─ Event 1: packageName="com.blocked.app"
  │   ├── debounce: passes (first event)
  │   ├── lastForegroundPackage guard: passes (new package)
  │   ├── handleRestrictedAppDetected:
  │   │   ├── LockVisibilityState.isLockVisible = false → passes
  │   │   ├── throttle: passes (first launch)
  │   │   └── HOME + launchLockActivity → LockVisibilityState.markLaunched()
  │   │
  ├─ Event 2 (50ms later): packageName="com.blocked.app"
  │   └── debounce: BLOCKED (500ms not elapsed)
  │
  ├─ Event 3 (200ms later): packageName=own package (LockActivity)
  │   └── debounce: BLOCKED
  │
  ├─ Event 4 (600ms later): packageName=own package (LockActivity)
  │   ├── debounce: passes
  │   ├── own package check: BLOCKED → return
  │
  ├─ Event 5 (700ms later): TYPE_WINDOWS_CHANGED, packageName="com.blocked.app"
  │   ├── debounce: BLOCKED (only 100ms since event 4)
  │
  └─ Event 6 (1200ms later): packageName="com.blocked.app"
      ├── debounce: passes
      ├── lastForegroundPackage="com.blocked.app" → same → BLOCKED
      └── (no action)
```

### 6.3 Unlock / Exit Path

```
User taps "OK" button on LockActivity
  │
  ▼
LockActivity.finishAndGoHome()
  ├── LockVisibilityState.markHidden()
  ├── startActivity(HOME intent)
  └── finish()
  │
  ▼
LockActivity.onDestroy()
  └── LockVisibilityState.markHidden() (safety net)
  │
  ▼
User is now on Home screen
  │
  ▼
AccessibilityEvent: launcher package
  ├── evaluateForegroundPackage: isLauncherPackage → return
  └── (no enforcement action)
```

### 6.4 Pause / Resume Interactions

```
Flutter calls pauseEnforcement(durationMs)
  │
  ▼
RestrictionsMethodHandler → SessionEnforcementUseCase.pauseEnforcement()
  ├── RestrictionManager.pauseFor(durationMs)
  ├── AlarmOrchestrator.rescheduleAll()
  ├── Dismiss LockActivity via broadcast (ACTION_DISMISS)
  └── SessionController.applyCurrentEnforcementState("pause_enforcement")
      ├── shouldMonitor=false → service.setMonitoringEnabled(false)
      └── LockActivity receives dismiss → finishAndGoHome()
  │
  ▼
(time passes, pause expires, alarm fires)
  │
  ▼
RestrictionAlarmReceiver → SessionController.applyCurrentEnforcementState("alarm_resume")
  ├── shouldMonitor=true → service.setMonitoringEnabled(true)
  └── service.enforceCurrentForegroundNow("alarm_resume")
      └── (if blocked app still foreground → handleRestrictedAppDetected)
```

---

## 7. Risks and Edge Cases

### 7.1 Background Activity Launch Restrictions (Android 10+)

**Risk**: Starting with Android 10 (API 29), apps cannot start activities from the background. An `AccessibilityService` context may be treated as "background" on some OEMs.

**Mitigation**:
- `AccessibilityService` is a foreground service by definition and generally exempt from BAL restrictions.
- Use `FLAG_ACTIVITY_NEW_TASK` (required for non-Activity context).
- If launch fails, catch the exception and fall back to `GLOBAL_ACTION_BACK` + retry on next event.
- On Android 14+ (API 34), Google tightened BAL further. Test with `adb shell am start --activity-task-on-home` to verify behavior. If blocked, consider posting a high-priority notification with a full-screen intent (`fullScreenIntent`) as a fallback path -- this is always allowed.

**Instrumentation**: Log `startActivity` success/failure with caught exceptions. Track in lifecycle events.

### 7.2 Timing Race: HOME Action vs. LockActivity Launch

**Risk**: `performGlobalAction(GLOBAL_ACTION_HOME)` is asynchronous. The launcher may not be foreground before `LockActivity` launches, causing:
- Brief flash of blocked app before lock appears.
- On slow devices, LockActivity may appear then immediately get covered by launcher.

**Mitigation**:
- Launch LockActivity *immediately* after HOME (don't `postDelayed`). The activity launch will be queued by the system.
- The `FLAG_ACTIVITY_NO_ANIMATION` flag reduces visual flicker.
- `singleInstance` with its own task avoids interference with the launcher task transition.
- OEM testing matrix should cover timing on Samsung (OneUI), Xiaomi (MIUI), Huawei (EMUI), and stock Pixel.

**Alternative**: If flicker is severe on some OEMs, add a 50-100ms `Handler.postDelayed` before launching LockActivity. This is a tunable constant.

### 7.3 Split-Screen / Multi-Window

**Risk**: In split-screen, the blocked app occupies one half. `GLOBAL_ACTION_HOME` may not fully dismiss it. `LockActivity` may open in only one half.

**Mitigation**:
- Detect multi-window mode: `windows` list will show multiple `TYPE_APPLICATION` windows. If split-screen is detected, also call `performGlobalAction(GLOBAL_ACTION_TOGGLE_SPLIT_SCREEN)` (API 24+) before HOME.
- LockActivity should call `requestedOrientation` carefully and avoid `resizeableActivity="false"` (which would crash on Samsung split-screen).
- Test scenario: open blocked app in split-screen with an allowed app.

### 7.4 Picture-in-Picture (PiP)

**Risk**: A blocked app in PiP mode won't trigger `TYPE_WINDOW_STATE_CHANGED` because PiP windows are not "focused."

**Mitigation**:
- In `getFocusedApplicationPackageName()`, additionally scan for `TYPE_APPLICATION` windows that are *not* focused but match a blocked package.
- On detection, call `performGlobalAction(GLOBAL_ACTION_HOME)` -- this collapses PiP on most devices.
- This is a known limitation that can be addressed in a follow-up iteration.

### 7.5 Recents Screen Bypass

**Risk**: User opens Recents, sees blocked app thumbnail, taps it. The transition from Recents to blocked app may not always fire `TYPE_WINDOW_STATE_CHANGED` reliably on all OEMs.

**Mitigation**:
- `TYPE_WINDOWS_CHANGED` events are more reliable for Recents transitions. The service already listens for both.
- The debounce (500ms) should be tested to ensure it doesn't suppress the Recents-to-app transition.
- Consider reducing debounce to 300ms if Recents bypass is observed.

### 7.6 Notification Shade / Quick Settings Bypass

**Risk**: User pulls down notification shade over the lock activity. From there they could tap a notification that opens the blocked app.

**Mitigation**:
- This is a *re-entry* scenario. When the blocked app comes foreground again, the accessibility service fires another event and re-triggers enforcement.
- The lock-visible guard must correctly handle this: if lock was visible but user navigated away via notification, `onPause`/`onStop` should NOT clear `isLockVisible` prematurely. Only `onDestroy` and explicit `finishAndGoHome()` should clear it.
- Additional hardening: in `LockActivity.onStop()`, if `!isFinishing`, re-launch self via `startActivity(intent)` to force back to foreground.

### 7.7 Settings / Open-by-Intent Bypass

**Risk**: User navigates to Settings > Apps > [blocked app] > Open, or uses a deep link intent from another app to launch the blocked app.

**Mitigation**: Both scenarios result in the blocked app becoming foreground, which triggers accessibility events normally. No special handling needed -- standard detection path covers this.

### 7.8 Process Death / Service Reconnection

**Risk**: Android may kill the accessibility service process. On reconnection (`onServiceConnected`), the service must re-evaluate state.

**Mitigation**:
- `onServiceConnected` already calls `resolveSessionState()` and `enforceCurrentForegroundNow()`. This is retained.
- `LockVisibilityState` is in-memory and will be reset on process death. `LockActivity` will also be destroyed. This is safe: when the service reconnects and detects a blocked app, it will re-launch `LockActivity`.
- If `LockActivity` is destroyed by the system but `LockVisibilityState.isLockVisible` was true, the state resets to `false` on process restart, so the guard won't incorrectly suppress a re-launch.

### 7.9 OEM-Specific Autostart / Battery Optimization

**Risk**: Some OEMs (Xiaomi, Huawei, Oppo, Vivo) aggressively kill background services and block activity launches.

**Mitigation**:
- Guide users to disable battery optimization for the app.
- On Xiaomi: guide to enable "Autostart" permission.
- The accessibility service is generally protected from aggressive killing, but activity launches from service context may be blocked on some MIUI versions.
- Instrumentation: log launch failures and surface them to Flutter via lifecycle events.

### 7.10 Screen Lock / Unlock

**Risk**: When screen is locked, accessibility events may still fire (e.g., an alarm app launches). When unlocked, a blocked app may be in foreground from before lock.

**Mitigation**:
- Add `KeyguardManager.isKeyguardLocked()` check in `onAccessibilityEvent`. Skip enforcement while screen is locked.
- On unlock, `TYPE_WINDOW_STATE_CHANGED` fires for whatever app is foreground. The normal detection path handles this.

### 7.11 Android 15+ Restrictions

**Risk**: Android 15 further restricts background activity starts and may introduce new accessibility service restrictions.

**Mitigation**:
- Monitor Android 15 developer previews for changes to `AccessibilityService.performGlobalAction` and BAL policies.
- The full-screen notification intent fallback (7.1) serves as a safety net.
- Test on Android 15 emulator before release.

---

## 8. Onboarding Flow: Enabling Accessibility Service

### 8.1 Reliable Enabled Check

The existing `AppMonitoringService.isRunning(context)` checks `Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES`. This is the correct approach and should be retained.

```kotlin
// Already exists in AppMonitoringService.Companion:
fun isRunning(context: Context): Boolean {
    val enabledServices = Settings.Secure.getString(
        context.contentResolver,
        Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES,
    )
    if (enabledServices.isNullOrEmpty()) return false
    val expectedService = ComponentName(context, AppMonitoringService::class.java).flattenToString()
    return enabledServices.split(':').any { it == expectedService }
}
```

**Enhancement**: Also check `Settings.Secure.ACCESSIBILITY_ENABLED` as a preliminary gate (fast check before string parsing).

### 8.2 High-Level Onboarding Flow

1. Flutter calls `checkPermission("android.accessibility")` (already exists via `PermissionHandler`).
2. If not granted, Flutter shows onboarding UI with instructions.
3. Flutter calls `requestPermission("android.accessibility")` which opens `Settings.ACTION_ACCESSIBILITY_SETTINGS`.
4. User enables the service manually in Settings.
5. On return to app, Flutter re-checks permission status.
6. `AppMonitoringService.onServiceConnected()` fires, initializes state.

No changes needed to onboarding -- the existing flow via `PermissionHandler` is compatible with the LockActivity approach.

---

## 9. Migration Path (Step-by-Step)

### Phase 1: Extract and Prepare (non-breaking)
1. Create `ShieldConfigStore.kt` -- extract persistence logic from `ShieldOverlayManager`.
2. Create `LockVisibilityState.kt` singleton.
3. Update `ConfigureShieldUseCase` to use `ShieldConfigStore` instead of `ShieldOverlayManager`.
4. Verify: existing overlay approach still works (no behavior change yet).

### Phase 2: Create LockActivity
5. Create `LockActivity.kt` with Compose UI reusing `ShieldOverlayContent`.
6. Add `LockActivity` to `AndroidManifest.xml`.
7. Add `Theme.PauzaLock` style resource.
8. Verify: LockActivity can be launched manually (test in isolation).

### Phase 3: Switch Enforcement
9. Modify `AppMonitoringService.handleRestrictedAppDetected` -- replace `ShieldOverlayManager.showShield()` with HOME + `launchLockActivity()`.
10. Modify `AppMonitoringService.evaluateForegroundPackage` -- replace overlay hide/show logic with `LockVisibilityState` checks and dismiss broadcasts.
11. Modify `AppMonitoringService.onInterrupt` and `onDestroy` -- replace `ShieldOverlayManager` cleanup with `LockActivity` dismiss.
12. Modify `RestrictionSessionController.applyCurrentEnforcementState` -- replace overlay hide with broadcast dismiss.
13. Modify `SessionEnforcementUseCase.pauseEnforcement` -- replace overlay hide with broadcast dismiss.

### Phase 4: Cleanup
14. Remove `ShieldOverlayManager.kt` (or mark `@Deprecated` for one release cycle).
15. Remove `OverlayViewTreeOwners.kt`.
16. Remove overlay-related WindowManager permissions if any were declared (none currently -- `TYPE_ACCESSIBILITY_OVERLAY` doesn't need separate permission).

### Phase 5: Harden
17. Add KeyguardManager check for screen-lock state.
18. Add multi-window detection and `GLOBAL_ACTION_TOGGLE_SPLIT_SCREEN`.
19. Add `LockActivity.onStop()` self-re-launch for notification shade bypass.
20. Add instrumentation logging for launch failures.

---

## 10. Definition of Done Checklist

### 10.1 Build-Time Criteria
- [ ] Project compiles without errors or warnings related to migration.
- [ ] `ShieldOverlayManager` references are removed from all active code paths (or deprecated).
- [ ] `LockActivity` is declared in `AndroidManifest.xml` with correct attributes.
- [ ] New style `Theme.PauzaLock` exists in resources.
- [ ] No lint errors related to new components.

### 10.2 Runtime Criteria
- [ ] `AppMonitoringService.isRunning()` returns correct state.
- [ ] `LockVisibilityState` correctly reflects LockActivity visibility at all times.
- [ ] `ShieldConfigStore` correctly loads/persists config (replacing overlay manager persistence).
- [ ] `LockActivity` receives and applies `ShieldConfig` from persisted store.
- [ ] Dismiss broadcast correctly finishes `LockActivity`.

### 10.3 Manual Test Matrix

| # | Scenario | Expected Behavior | Pass? |
|---|---|---|---|
| 1 | Open blocked app from launcher | HOME fires, LockActivity appears fullscreen | |
| 2 | Open allowed app from launcher | App opens normally, no interference | |
| 3 | Rapid switch: blocked -> allowed -> blocked (< 1s) | Lock appears, dismissed, re-appears; no crash/ANR | |
| 4 | Rapid switch: blocked A -> blocked B | Lock shows for B (or A then B) | |
| 5 | Press back on LockActivity | Nothing happens (back blocked) | |
| 6 | Press home on LockActivity | LockActivity finishes, user on home | |
| 7 | Tap primary button on LockActivity | LockActivity finishes, user on home | |
| 8 | Screen off/on while blocked app was foreground | Lock re-appears after unlock | |
| 9 | Rotate device while LockActivity is showing | LockActivity survives, no crash | |
| 10 | Open recents while LockActivity is showing | LockActivity not in recents list | |
| 11 | Open blocked app from recents | Blocked and re-locked | |
| 12 | Split-screen with blocked app | Blocked app dismissed from split | |
| 13 | Pull notification shade over LockActivity | Lock re-asserts on return | |
| 14 | Open blocked app via Settings > Apps > Open | Blocked and locked | |
| 15 | Open blocked app via deep link | Blocked and locked | |
| 16 | Pause enforcement while lock is showing | Lock dismisses immediately | |
| 17 | Resume enforcement while blocked app is foreground | Lock appears | |
| 18 | End session while lock is showing | Lock dismisses immediately | |
| 19 | Start session while blocked app is foreground | Lock appears | |
| 20 | Service killed by system, then reconnects | Re-evaluates and locks if needed | |
| 21 | Flutter `configureShield` then blocked app | Lock shows with custom config | |

### 10.4 Regression Checks
- [ ] All existing `RestrictionsMethodHandler` method channel APIs return correct results.
- [ ] `startSession` / `endSession` / `pauseEnforcement` / `resumeEnforcement` work as before.
- [ ] Lifecycle events are logged correctly for START/PAUSE/RESUME/END transitions.
- [ ] Alarm-based schedule transitions still trigger enforcement correctly.
- [ ] `BOOT_COMPLETED` / `MY_PACKAGE_REPLACED` receivers still reschedule alarms.
- [ ] `configureShield` from Flutter persists and loads correctly in LockActivity.
- [ ] `getRestrictionSession` returns accurate state during lock.

---

## 11. Assumptions

1. **LockActivity can use Compose**: The project already has Compose dependencies (for overlay). LockActivity will extend `ComponentActivity` and use `setContent {}`.

2. **No new permissions needed**: `TYPE_ACCESSIBILITY_OVERLAY` permission is not used for the new approach. Activity launches from an accessibility service context are allowed on supported API levels.

3. **Flutter host app is not affected**: `LockActivity` runs in its own task (`:pauza_lock` affinity) and does not interfere with the Flutter engine or its activity.

4. **`ShieldOverlayContent` composable is portable**: It currently takes `ShieldConfig` + callbacks. It can be reused in `LockActivity` without modification.

5. **Broadcast receiver for dismiss is sufficient**: An alternative would be using `LocalBroadcastManager` or an event bus, but a regular broadcast with `setPackage` scoping is simpler and works across process boundaries if needed.
