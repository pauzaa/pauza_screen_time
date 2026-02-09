# iOS setup

iOS support uses Apple’s **Screen Time** APIs:
- `FamilyControls` for authorization and app selection (picker)
- `ManagedSettings` for enforcing app restrictions
- `DeviceActivity` for rendering usage reports

Because of Apple privacy rules, iOS has important constraints:
- You cannot enumerate installed apps programmatically.
- You cannot read usage stats as data; you can only **render** them as a native report.

Copy-ready host app checklist:
- `docs/templates/PauzaHostAppIntegrationChecklist.md`

## Requirements

- iOS **16.0+** (this plugin requests individual authorization via `AuthorizationCenter.requestAuthorization(for: .individual)`).

## 1) Enable Screen Time on the device (developer sanity check)

### Why this is needed

If Screen Time is disabled system-wide, the user cannot approve Family Controls authorization.

### How to verify

On the test device: **Settings → Screen Time → Turn On Screen Time**.

## 2) Add App Groups (recommended; required for shield configuration sharing)

### Why this is needed

The plugin can store shield configuration in an **App Group** so it’s accessible to app extensions (for example, a Shield Configuration extension).

On native iOS, the plugin resolves the App Group identifier in this order:
1) `ShieldConfiguration(appGroupId: ...)` (Dart, optional)
2) `Info.plist` key `AppGroupIdentifier`
3) fallback to `group.<bundleId>`

### Xcode steps

1) Open `ios/Runner.xcworkspace` in Xcode
2) Select **Runner** target
3) Go to **Signing & Capabilities**
4) Click **+ Capability** → add **App Groups**
5) Add an app group, e.g. `group.com.yourcompany.yourapp`

### Add the `Info.plist` key (recommended)

In your app `Info.plist`, add:
- Key: `AppGroupIdentifier`
- Value: `group.com.yourcompany.yourapp`

### How to verify

- When you call `configureShield(...)` with `appGroupId`, you should not see iOS `INTERNAL_FAILURE`.
- If you do see `INTERNAL_FAILURE` with App Group diagnostics, your App Group is missing or not enabled for the running target.

## 3) Request Screen Time authorization

### Why this is needed

Without authorization, iOS will not allow app restriction APIs to operate.

### Dart code

```dart
final permissions = PermissionManager();
final granted = await permissions.requestIOSPermission(IOSPermission.familyControls);
```

### How to verify

- The system dialog appears.
- After approval, `checkIOSPermission(IOSPermission.familyControls)` returns `PermissionStatus.granted`.

## 4) Enable reliable pause auto-resume (Device Activity Monitor extension)

### Why this is needed

`pauseEnforcement(Duration)` on iOS now schedules a `DeviceActivity` interval and clears managed shields immediately.

To make auto-resume reliable while the app is backgrounded/terminated, your host app must include a **Device Activity Monitor Extension** that re-applies stored restrictions when the monitored pause interval ends.

### Required integration steps

1) In Xcode: **File → New → Target**
2) Choose **Device Activity Monitor Extension**
3) Enable **App Groups** capability for both targets:
   - **Runner**
   - **Device Activity Monitor Extension**
4) Use the same App Group ID for both targets (for example `group.com.yourcompany.yourapp`)
5) Add `AppGroupIdentifier` in both `Info.plist` files (Runner + extension) with that same value
6) Copy template file `docs/templates/PauzaDeviceActivityMonitorExtension.swift` into your extension target
7) Ensure your extension handles activity name `pauza_pause_auto_resume`

### Shared storage keys used by the plugin

The extension must read these App Group keys:
- `desiredRestrictedApps`
- `pausedUntilEpochMs`
- `manualEnforcementEnabled`
- `scheduleEnabled`
- `restrictionSchedules`
- `scheduledModesEnabled`
- `scheduledModes`

### Failure behavior

If iOS cannot start the pause monitor interval, `pauseEnforcement(...)` returns `INTERNAL_FAILURE` with an actionable diagnostic.

### How to verify timed auto-resume

1) Restrict at least one app token  
2) Call `pauseEnforcement(const Duration(minutes: 1))`  
3) Open a restricted app and keep it open  
4) After pause expiry, confirm the shield is re-applied automatically

## 5) Create the Shield Configuration extension (optional but recommended)

### Why this is needed

If you want a custom “shield” UI (the system screen shown when an app is restricted), iOS requires a **Shield Configuration Extension** target.

This plugin includes a copy-ready template:
- `docs/templates/PauzaShieldConfigurationExtension.swift`

Extensions live in the host app, so copy/adapt that file into your Shield Configuration extension target.

### Xcode steps

1) In Xcode: **File → New → Target**
2) Choose **Shield Configuration Extension**
3) Enable **App Groups** capability for the extension target too (same group ID)
4) Add `AppGroupIdentifier` in extension `Info.plist` (same value as Runner)
5) Copy `docs/templates/PauzaShieldConfigurationExtension.swift` into the extension target
6) Confirm extension reads key `shieldConfiguration` from App Group `UserDefaults`

## 6) Create the Device Activity Report extension (required for `UsageReportView`)

### Why this is needed

`UsageReportView` embeds a native `DeviceActivityReport` which only works if your app has a **Device Activity Report extension** target.

The Dart widget passes:
- `reportContext` (string, e.g. `daily`)
- `segment` (`daily` or `hourly`)
- `startTimeMs` / `endTimeMs`

The iOS side turns `reportContext` into `DeviceActivityReport.Context(reportContextId)`.

Template provided:
- `docs/templates/PauzaDeviceActivityReportExtension.swift`

### Xcode steps

1) In Xcode: **File → New → Target**
2) Choose **Device Activity Report Extension**
3) Ensure the extension supports iOS 16+
4) Copy `docs/templates/PauzaDeviceActivityReportExtension.swift` into the extension target
5) Ensure your Dart `reportContext` matches a context implemented by the extension (template provides `daily`)

### How to verify

- Build and run on a real device
- Render:

```dart
IOSUsageReportView(
  reportContext: 'daily',
  startDate: DateTime.now().subtract(const Duration(days: 1)),
  endDate: DateTime.now(),
)
```

If the extension is missing, the view will not render correctly.

## Next

- [Restrict / block apps](restrict-apps.md)
- [Usage stats](usage-stats.md)
- [Troubleshooting](troubleshooting.md)
