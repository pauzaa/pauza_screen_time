# Troubleshooting

This page lists common setup issues and how to fix them.

## Android

### Blocking doesn’t show when I open a restricted app

**Likely cause**: Accessibility service is not enabled.

**Fix**:
- Open **Settings → Accessibility**
- Enable your app’s accessibility service

**Verify**:
- Restrict a well-known app (e.g. a browser) and open it — the overlay should appear within ~500ms.

### Restriction mutation methods fail with `MISSING_PERMISSION` on Android

**What it means**:

Restriction prerequisites are not satisfied. For Android restrictions, this means Accessibility is disabled.

Affected methods:
- `upsertMode(...)`
- `setModesEnabled(...)`
- `startSession(...)`
- `pauseEnforcement(...)`
- `resumeEnforcement()`

**Fix**:
- Open **Settings → Accessibility**
- Enable your app’s accessibility service
- Retry the restriction call

### Blocking triggers, but shield overlay is not visible

**Likely cause**: Accessibility service is enabled, but the plugin’s overlay failed to render due to OEM restrictions or the service not being fully active yet.

**Fix**:
- Confirm your app’s accessibility service is enabled (see above)
- Re-open your app, then try again
- Try on a different device/OEM to rule out vendor-specific overlay restrictions

### Usage stats are empty

**Likely cause**: Usage Access is not granted.

**Fix**:
- Open **Settings → Usage access**
- Allow your app

### Pause expires but app is still usable

**Likely cause**: pause is still active or no enforceable mode is active.

**Fix**:
- Check `getRestrictionSession()`
- Ensure there is a persisted enforceable mode (`schedule != null` with blocked apps) or an active manual mode
- Confirm Accessibility service is still enabled

**Verify**:
- `getRestrictionSession().pausedUntil` becomes `null` after pause end
- `getRestrictionSession().isPausedNow` becomes `false` (derived from `pausedUntil`)
- Opening a restricted app shows the shield again

## iOS

### `requestIOSPermission(...)` returns false

**Likely causes**:
- Screen Time is disabled on the device
- user tapped “Don’t Allow”
- device is not iOS 16+

**Fix**:
- **Settings → Screen Time → Turn On Screen Time**
- Re-run and request authorization again

### Restriction mutation methods fail with `MISSING_PERMISSION` on iOS

**What it means**:

Screen Time authorization has not been granted yet (`notDetermined`).

Affected methods:
- `upsertMode(...)`
- `setModesEnabled(...)`
- `startSession(...)`
- `pauseEnforcement(...)`
- `resumeEnforcement()`

**Fix**:
- Call `requestIOSPermission(IOSPermission.familyControls)` first
- Retry restriction calls after approval

### Restriction mutation methods fail with `PERMISSION_DENIED` on iOS

**What it means**:

Screen Time authorization was denied.

**Fix**:
- Ask user to enable Screen Time authorization in system settings
- Retry after authorization is approved

### `UsageReportView` shows nothing / fails to render

**Likely cause**: missing **Device Activity Report extension** target.

**Fix**:
- Follow [iOS setup](ios-setup.md) step “Device Activity Report extension”
- Ensure your extension supports the same `reportContext` you pass from Dart (for example `daily`)

### iOS `INTERNAL_FAILURE` after calling `configureShield()`

**What it means**:

The plugin tried to store shield configuration into the resolved App Group, but App Group storage failed.

**Fix**:
- Add **App Groups** capability to:
  - Runner target
  - Shield Configuration extension target (if you use it)
- Ensure both use the same app group identifier
- Add `Info.plist` key `AppGroupIdentifier` or pass `ShieldConfiguration(appGroupId: ...)`

### iOS `INVALID_ARGUMENT` when restricting tokens

**What it means**:

One or more tokens you passed to restrictions could not be decoded as iOS `ApplicationToken`.

**Fix**:
- Only use tokens returned from `InstalledAppsManager.selectIOSApps()`
- Don’t trim/alter the base64 string when storing it

### iOS pause did not auto-resume while app was backgrounded

**Likely causes**:
- missing **Device Activity Monitor extension** setup
- extension target does not handle activity name `pauza_pause_auto_resume`
- Runner and extension do not share the same App Group storage

**Fix**:
- Follow [iOS setup](ios-setup.md) step “Enable reliable pause auto-resume (Device Activity Monitor extension)”
- Ensure Runner and monitor extension share the same App Group ID
- Ensure both `Info.plist` files contain matching `AppGroupIdentifier`
- Ensure the extension re-applies blocked ids from the active mode after `pausedUntilEpochMs` expiry

### iOS/Android pause call fails with `INVALID_ARGUMENT`

**Likely causes**:
- duration is missing/zero/negative
- duration is `>= 24h` (both Android and iOS)
- enforcement is already paused

**Fix**:
- Pass a positive duration (for example `Duration(minutes: 5)`)
- Check `getRestrictionSession().isPausedNow` (or `pausedUntil != null`) before re-pausing

## Next

- [Docs index](README.md)
- [Permissions](permissions.md)
- [Restrict / block apps](restrict-apps.md)
