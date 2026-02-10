# Restrict / block apps

This guide covers `AppRestrictionManager` with the mode-centric API.

## Core model

Restrictions are defined by `RestrictionMode`:
- `modeId`: unique id
- `blockedAppIds`: app identifiers to shield
- `schedule` (optional): when the mode is automatically active

Use `upsertMode` to create/update a mode.

## 1) Configure shield UI

```dart
await AppRestrictionManager().configureShield(const ShieldConfiguration(
  title: 'Restricted',
  subtitle: 'Ask a parent for more time.',
  appGroupId: 'group.com.yourcompany.yourapp',
));
```

## 2) Create / update a mode

```dart
final restrictions = AppRestrictionManager();

await restrictions.upsertMode(
  RestrictionMode(
    modeId: 'focus-mode',
    schedule: const RestrictionSchedule(
      daysOfWeekIso: {1, 2, 3, 4, 5},
      startMinutes: 9 * 60,
      endMinutes: 12 * 60,
    ),
    blockedAppIds: [
      AppIdentifier.android('com.instagram.android'),
    ],
  ),
);

await restrictions.setModesEnabled(true);
```

Notes:
- Schedules are optional per mode.
- Overlap validation applies only to scheduled modes.
- Scheduled overlaps return `INVALID_ARGUMENT`.

## 3) Manual mode session

```dart
await restrictions.startSession(
  RestrictionMode(
    modeId: 'focus-mode',
    blockedAppIds: [
      AppIdentifier.android('com.instagram.android'),
    ],
  ),
);
await restrictions.endSession();
```

Manual session rules:
- `startSession(mode)` always requires and uses the full mode DTO (`modeId` + non-empty `blockedAppIds`).
- `startSession(mode)` writes the active session snapshot separately from recurring scheduled modes.
- Manual session overrides scheduled activation until `endSession()`.

## 4) Pause / resume

```dart
await restrictions.pauseEnforcement(const Duration(minutes: 5));
await restrictions.resumeEnforcement();
```

## 5) Restriction session snapshot

```dart
final session = await restrictions.getRestrictionSession();
```

`RestrictionSession` fields:
- `isActiveNow`
- `isPausedNow`
- `isManuallyEnabled`
- `isScheduleEnabled`
- `isInScheduleNow`
- `pausedUntil`
- `restrictedApps`
- `activeModeId`
- `activeModeSource` (`none` | `manual` | `schedule`)

## 6) Modes config snapshot

```dart
final config = await restrictions.getModesConfig();
```

Returns:
- `enabled`: global schedule engine flag
- `modes`: only persisted scheduled modes used for background enforcement (`schedule != null && blockedAppIds.isNotEmpty`)

The plugin persists only enforceable scheduled modes and the current active session snapshot. Host apps should store the full user mode catalog separately and represent disabled schedules by removing the schedule-backed mode from plugin storage.

## 7) Remove mode

```dart
await restrictions.removeMode('focus-mode');
```

If the removed mode is currently active, the active session is cleared.

## Breaking migration map

- `restrictApps`, `restrictApp`, `unrestrictApp`, `clearAllRestrictions` -> `upsertMode` / `removeMode`
- `upsertScheduledMode`, `removeScheduledMode`, `setScheduledModesEnabled`, `getScheduledModesConfig` -> `upsertMode`, `removeMode`, `setModesEnabled`, `getModesConfig`
- `startRestrictionSession`, `endRestrictionSession` -> `startSession(mode)`, `endSession()`
