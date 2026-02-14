/// Lifecycle transition event emitted by native restriction engines.
class RestrictionLifecycleEvent {
  const RestrictionLifecycleEvent({
    required this.id,
    required this.sessionId,
    required this.modeId,
    required this.action,
    required this.source,
    required this.reason,
    required this.occurredAt,
  });

  final String id;
  final String sessionId;
  final String modeId;
  final RestrictionLifecycleAction action;
  final RestrictionLifecycleSource source;
  final String reason;
  final DateTime occurredAt;

  factory RestrictionLifecycleEvent.fromMap(Map<String, dynamic> map) {
    final id = (map['id'] as String? ?? '').trim();
    final sessionId = (map['sessionId'] as String? ?? '').trim();
    final modeId = (map['modeId'] as String? ?? '').trim();
    final actionRaw = (map['action'] as String? ?? '').trim();
    final sourceRaw = (map['source'] as String? ?? '').trim();
    final reason = (map['reason'] as String? ?? '').trim();
    final occurredAtEpochMs = switch (map['occurredAtEpochMs']) {
      final int value => value,
      final num value => value.toInt(),
      _ => null,
    };

    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'Event id cannot be empty');
    }
    if (sessionId.isEmpty) {
      throw ArgumentError.value(
        sessionId,
        'sessionId',
        'Session id cannot be empty',
      );
    }
    if (modeId.isEmpty) {
      throw ArgumentError.value(modeId, 'modeId', 'Mode id cannot be empty');
    }
    final action = RestrictionLifecycleAction.fromWire(actionRaw);
    final source = RestrictionLifecycleSource.fromWire(sourceRaw);
    if (reason.isEmpty) {
      throw ArgumentError.value(reason, 'reason', 'Reason cannot be empty');
    }
    if (occurredAtEpochMs == null || occurredAtEpochMs <= 0) {
      throw ArgumentError.value(
        occurredAtEpochMs,
        'occurredAtEpochMs',
        'Timestamp must be positive',
      );
    }

    return RestrictionLifecycleEvent(
      id: id,
      sessionId: sessionId,
      modeId: modeId,
      action: action,
      source: source,
      reason: reason,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(
        occurredAtEpochMs,
        isUtc: true,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'sessionId': sessionId,
      'modeId': modeId,
      'action': action.wireValue,
      'source': source.wireValue,
      'reason': reason,
      'occurredAtEpochMs': occurredAt.toUtc().millisecondsSinceEpoch,
    };
  }
}

enum RestrictionLifecycleAction {
  start('START'),
  pause('PAUSE'),
  resume('RESUME'),
  end('END');

  const RestrictionLifecycleAction(this.wireValue);

  final String wireValue;

  static RestrictionLifecycleAction fromWire(String raw) {
    return switch (raw) {
      'START' => RestrictionLifecycleAction.start,
      'PAUSE' => RestrictionLifecycleAction.pause,
      'RESUME' => RestrictionLifecycleAction.resume,
      'END' => RestrictionLifecycleAction.end,
      _ => throw ArgumentError.value(raw, 'action', 'Unsupported action'),
    };
  }
}

enum RestrictionLifecycleSource {
  manual('manual'),
  schedule('schedule');

  const RestrictionLifecycleSource(this.wireValue);

  final String wireValue;

  static RestrictionLifecycleSource fromWire(String raw) {
    return switch (raw) {
      'manual' => RestrictionLifecycleSource.manual,
      'schedule' => RestrictionLifecycleSource.schedule,
      _ => throw ArgumentError.value(raw, 'source', 'Unsupported source'),
    };
  }
}
