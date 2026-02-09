# Pauza iOS Host App Integration Checklist

Use this checklist in your iOS host app repo when integrating `pauza_screen_time`.

## 1) Baseline requirements

- [ ] Deployment target is iOS 16.0+
- [ ] Test on a real device (not simulator-only)
- [ ] Screen Time is enabled on the device

## 2) Runner target setup

- [ ] Open `ios/Runner.xcworkspace` in Xcode
- [ ] Add **App Groups** capability on **Runner**
- [ ] Create/use a shared App Group ID (example: `group.com.yourcompany.yourapp`)
- [ ] Add `AppGroupIdentifier` in Runner `Info.plist` with that same group ID

## 3) Device Activity Monitor Extension (required for reliable pause auto-resume)

- [ ] Add target: **Device Activity Monitor Extension**
- [ ] Add **App Groups** capability on the extension target
- [ ] Use the same App Group ID as Runner
- [ ] Add `AppGroupIdentifier` in extension `Info.plist` (same value)
- [ ] Copy `docs/templates/PauzaDeviceActivityMonitorExtension.swift` into this target
- [ ] Confirm extension handles activity name `pauza_pause_auto_resume`

## 4) Shield Configuration Extension (optional, recommended for custom shield UI)

- [ ] Add target: **Shield Configuration Extension**
- [ ] Add **App Groups** capability on the extension target
- [ ] Use the same App Group ID as Runner
- [ ] Add `AppGroupIdentifier` in extension `Info.plist` (same value)
- [ ] Copy `docs/templates/PauzaShieldConfigurationExtension.swift` into this target
- [ ] Verify the extension reads `shieldConfiguration` from App Group defaults

## 5) Device Activity Report Extension (required for `IOSUsageReportView`)

- [ ] Add target: **Device Activity Report Extension**
- [ ] Ensure target supports iOS 16+
- [ ] Copy `docs/templates/PauzaDeviceActivityReportExtension.swift` into this target
- [ ] Ensure report contexts match Dart usage (template includes `daily`)

## 6) Entitlements and signing checks

- [ ] Runner and each extension use matching Team/signing setup
- [ ] Runner and each extension include App Groups entitlement with the same group ID
- [ ] Build succeeds for Runner + all extension targets

## 7) Runtime verification checklist

- [ ] `requestIOSPermission(IOSPermission.familyControls)` succeeds
- [ ] `selectIOSApps()` returns tokens
- [ ] `restrictApps(...)` applies shields to selected apps
- [ ] `pauseEnforcement(Duration(minutes: 1))` clears restrictions immediately
- [ ] At pause expiry, shield is re-applied automatically without reopening host app
- [ ] `IOSUsageReportView(reportContext: 'daily', ...)` renders successfully

## 8) Common failure diagnostics

- [ ] `INTERNAL_FAILURE` with App Group diagnostics: verify App Group capability + `AppGroupIdentifier` in both Runner and extension targets
- [ ] Pause does not auto-resume in background: verify Device Activity Monitor extension exists and handles `pauza_pause_auto_resume`
- [ ] Usage report view does not render: verify Device Activity Report extension exists and report context matches Dart
