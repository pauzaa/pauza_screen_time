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
- `endSession()`
- `configureShield(...)`

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
- `activeMode` (`RestrictionMode?`)
- `activeModeSource` (`none` | `manual` | `schedule`)

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
