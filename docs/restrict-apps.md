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
  duration: const Duration(minutes: 30), // optional
);
await restrictions.endSession();
```

Manual session rules:
- `startSession(mode, {duration})` always requires and uses the full mode DTO (`modeId` + non-empty `blockedAppIds`).
- `duration` is optional and only applies to manual starts.
- If provided, `duration` must be `> 0` and `< 24h`.
- `startSession(...)` fails with `INVALID_ARGUMENT` when any restriction session is already active (`manual` or `schedule`).
- `startSession(...)` writes the active session snapshot separately from recurring scheduled modes.
- Manual session overrides scheduled activation until `endSession()`.
- `endSession()` requires an active session and returns `INVALID_ARGUMENT` if none is active.
- `endSession()` always clears the active session regardless of source (`manual` or `schedule`).
- If `endSession()` ends a schedule session during its active interval, reactivation is suppressed until that interval ends.

## 4) Pause / resume

```dart
await restrictions.pauseEnforcement(const Duration(minutes: 5));
await restrictions.resumeEnforcement();
```

Pause/resume validation rules:
- `pauseEnforcement(duration)` requires an active restriction session.
- `pauseEnforcement(duration)` requires that enforcement is not currently paused.
- `pauseEnforcement(duration)` duration must be `> 0` and `< 24h`.
- `resumeEnforcement()` requires an active restriction session.
- `resumeEnforcement()` requires that enforcement is currently paused.
- Validation failures return `INVALID_ARGUMENT` with clear messages:
  - `No active restriction session to pause.`
  - `Restriction enforcement is already paused.`
  - `No active restriction session to resume.`
  - `Restriction enforcement is not paused.`

## Permission fast-failure coverage

Restriction mutation methods that can enable or apply enforcement fail fast when
restriction prerequisites are missing.

- Android prerequisite: Accessibility service enabled.
- iOS prerequisite: Screen Time authorization approved.

Methods that can throw permission errors (`MISSING_PERMISSION`,
`PERMISSION_DENIED`, `SYSTEM_RESTRICTED` where applicable):
- `upsertMode(...)`
- `setModesEnabled(...)`
- `startSession(...)`
- `pauseEnforcement(...)`
- `resumeEnforcement()`

Methods that do not preflight-fail and still return state/cleanup behavior:
- `getRestrictionSession()`
- `isRestrictionSessionActiveNow()`
- `getModesConfig()`
- `removeMode(...)`
- `endSession()` (still returns `INVALID_ARGUMENT` when no active session exists)
- `configureShield(...)`

## 5) Restriction session snapshot

```dart
final session = await restrictions.getRestrictionSession();
```

`RestrictionState` fields:
- `isActiveNow`
- `isPausedNow`
- `isManuallyEnabled`
- `isScheduleEnabled`
- `isInScheduleNow`
- `pausedUntil`
- `activeMode` (`RestrictionMode?`)
- `activeModeSource` (`none` | `manual` | `schedule`)
- `currentSessionEvents` (`List<RestrictionLifecycleEvent>`, active-session pending events only)

Derived semantics:
- `isActiveNow == (activeMode != null)`
- `isPausedNow == (pausedUntil != null)`

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

## 8) Lifecycle events queue (durable transition log)

Use lifecycle events when your host app needs complete mode history, including
scheduled/background transitions.

```dart
final restrictions = AppRestrictionManager();

final events = await restrictions.getPendingLifecycleEvents(limit: 200);
if (events.isNotEmpty) {
  // 1) Persist idempotently in your DB (keyed by event.id)
  // 2) Ack only after successful commit
  await restrictions.ackLifecycleEvents(
    throughEventId: events.last.id,
  );
}
```

New APIs:
- `getPendingLifecycleEvents({int limit = 200})`
- `ackLifecycleEvents({required String throughEventId})`

Delivery semantics:
- Ordered oldest-first within the plugin queue.
- At-least-once delivery.
- Redelivery occurs until acknowledged.
- Ack is inclusive (`<= throughEventId` is removed).

Important:
- Persist before ack.
- Use idempotent insert (`event.id` unique) to handle redelivery.
- Recommended polling triggers: app startup, app foreground resume, and after
  manual restriction mutations.

## Next

- [Docs index](README.md)
- [Permissions](permissions.md)
- [Installed apps](installed-apps.md)
- [Restriction lifecycle events](restriction-lifecycle-events.md)
- [Troubleshooting](troubleshooting.md)
