# Restriction Lifecycle Events

This guide explains how to ingest durable restriction lifecycle transitions from
`pauza_screen_time` into a host app database.

Use this API when you need complete history for:
- `START`
- `PAUSE`
- `RESUME`
- `END`

## Why this exists

Manual transitions can be observed from UI calls, but scheduled transitions are
executed in native background flows:
- Android alarms/receivers
- iOS DeviceActivity monitor extension callbacks

Without plugin lifecycle queue ingestion, host-side logs can be incomplete when
the app is backgrounded or terminated.

## API

```dart
final restrictions = AppRestrictionManager();

final events = await restrictions.getPendingLifecycleEvents(limit: 200);
await restrictions.ackLifecycleEvents(throughEventId: events.last.id);
```

- `getPendingLifecycleEvents({int limit = 200})`
  - Returns oldest-first pending events.
  - `limit` must be positive.
- `ackLifecycleEvents({required String throughEventId})`
  - Inclusive ack checkpoint.
  - Removes events with `id <= throughEventId`.

## Event data contract

`RestrictionLifecycleEvent` fields:
- `id`: unique queue event id (monotonic-friendly string)
- `sessionId`: logical restriction session id
- `modeId`: mode identifier
- `action`: `START | PAUSE | RESUME | END`
- `source`: `manual | schedule`
- `reason`: transition reason tag for diagnostics
- `occurredAt`: Dart `DateTime` parsed from native epoch millis

Native payload includes `occurredAtEpochMs`; Dart exposes `occurredAt`.
The current API does not include `modeTitleSnapshot`.

## Transition semantics

Transition mapping:
- inactive -> active: `START`
- active -> inactive: `END`
- unpaused -> paused: `PAUSE`
- paused -> unpaused: `RESUME`

Additional rules:
- Active mode/source switch emits `END` then `START`.
- Pause auto-expiry emits `RESUME` only if the session remains active.
- If a schedule ended during pause, no extra `RESUME` is emitted.

## Queue semantics and guarantees

- Ordered oldest-first.
- At-least-once delivery.
- Redelivery before ack is expected.
- Bounded queue capacity with deterministic oldest-first pruning.

Implementation note:
- Native queue storage uses a cursor-indexed internal layout for efficient
  reads/acks; host-facing semantics above are unchanged.

Implication:
- Host ingestion must be idempotent.

## Platform behavior notes

- Android: scheduled/background transitions are emitted from alarm/receiver
  flows and pause-end alarm flow, not only from Flutter UI calls.
- iOS: scheduled/background transitions are emitted from DeviceActivity monitor
  extension callbacks (`intervalDidStart`/`intervalDidEnd`) into shared App
  Group storage.

Host apps cannot reliably reconstruct these transitions from app lifecycle.

## Host integration guide

### 1) DB schema (recommended)

```sql
CREATE TABLE restriction_lifecycle_events (
  id TEXT PRIMARY KEY,
  session_id TEXT NOT NULL,
  mode_id TEXT NOT NULL,
  action TEXT NOT NULL CHECK (action IN ('START','PAUSE','RESUME','END')),
  source TEXT NOT NULL CHECK (source IN ('manual','schedule')),
  reason TEXT NOT NULL,
  occurred_at_epoch_ms INTEGER NOT NULL
);
```

### 2) Idempotent insert pattern

Use `INSERT OR IGNORE` (SQLite) keyed by `id`.

```sql
INSERT OR IGNORE INTO restriction_lifecycle_events
  (id, session_id, mode_id, action, source, reason, occurred_at_epoch_ms)
VALUES (?, ?, ?, ?, ?, ?, ?);
```

### 3) Sync loop

```dart
Future<void> syncRestrictionLifecycleEvents(AppRestrictionManager manager) async {
  while (true) {
    final events = await manager.getPendingLifecycleEvents(limit: 200);
    if (events.isEmpty) return;

    await db.transaction(() async {
      for (final event in events) {
        await repo.insertIgnore(event); // idempotent by event.id
      }
    });

    await manager.ackLifecycleEvents(
      throughEventId: events.last.id,
    );
  }
}
```

### 4) Recommended sync triggers

- app startup
- app foreground resume
- immediately after manual lifecycle actions (`startSession`, `endSession`,
  `pauseEnforcement`, `resumeEnforcement`)

## Failure and recovery behavior

If app crashes after insert but before ack:
- plugin redelivers same events
- idempotent insert prevents duplicates
- next sync can ack safely

If plugin redelivers previously fetched events:
- expected with at-least-once delivery
- handle via unique `id` constraint

If queue hits capacity:
- oldest events are pruned first
- reduce sync latency and run sync on startup/resume to avoid backlog growth

## Host checklist

1. Add DB migration for lifecycle events table.
2. Implement repository sync from plugin queue.
3. Persist with idempotent insert by `id`.
4. Ack only after successful transaction commit.
5. Trigger sync on startup and resume.
6. Add integration tests for duplicate redelivery and inclusive ack behavior.

## Versioning and upgrade notes

- Feature is additive and backward compatible.
- Requires plugin version `0.6.0` or later.
- Ship ingestion before relying on lifecycle analytics/history.
