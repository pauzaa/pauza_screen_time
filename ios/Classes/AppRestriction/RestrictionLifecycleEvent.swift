import Foundation

enum RestrictionLifecycleAction: String {
    case start = "START"
    case pause = "PAUSE"
    case resume = "RESUME"
    case end = "END"
}

enum RestrictionLifecycleSource: String {
    case manual
    case schedule

    init?(modeSource: RestrictionModeSource) {
        switch modeSource {
        case .manual:
            self = .manual
        case .schedule:
            self = .schedule
        case .none:
            return nil
        }
    }
}

struct RestrictionLifecycleEventDraft {
    let sessionId: String
    let modeId: String
    let action: RestrictionLifecycleAction
    let source: RestrictionLifecycleSource
    let reason: String
    let occurredAtEpochMs: Int64
}

struct RestrictionLifecycleEvent {
    let id: String
    let sessionId: String
    let modeId: String
    let action: RestrictionLifecycleAction
    let source: RestrictionLifecycleSource
    let reason: String
    let occurredAtEpochMs: Int64

    func toStorageMap() -> [String: Any] {
        return [
            "id": id,
            "sessionId": sessionId,
            "modeId": modeId,
            "action": action.rawValue,
            "source": source.rawValue,
            "reason": reason,
            "occurredAtEpochMs": occurredAtEpochMs,
        ]
    }

    func toChannelMap() -> [String: Any] {
        return toStorageMap()
    }

    init?(_ map: [String: Any]) {
        let id = (map["id"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sessionId = (map["sessionId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let modeId = (map["modeId"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let actionRaw = (map["action"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceRaw = (map["source"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let reason = (map["reason"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let occurredAtEpochMs: Int64 = {
            if let number = map["occurredAtEpochMs"] as? NSNumber {
                return number.int64Value
            }
            if let value = map["occurredAtEpochMs"] as? Int64 {
                return value
            }
            if let value = map["occurredAtEpochMs"] as? Int {
                return Int64(value)
            }
            return -1
        }()

        guard !id.isEmpty,
              !sessionId.isEmpty,
              !modeId.isEmpty,
              !reason.isEmpty,
              occurredAtEpochMs > 0,
              let action = RestrictionLifecycleAction(rawValue: actionRaw),
              let source = RestrictionLifecycleSource(rawValue: sourceRaw) else {
            return nil
        }
        self.id = id
        self.sessionId = sessionId
        self.modeId = modeId
        self.action = action
        self.source = source
        self.reason = reason
        self.occurredAtEpochMs = occurredAtEpochMs
    }
}

struct RestrictionLifecycleSnapshot {
    let isActive: Bool
    let isPaused: Bool
    let modeId: String?
    let source: RestrictionModeSource
    let sessionId: String?

    static func inactive(isPaused: Bool) -> RestrictionLifecycleSnapshot {
        RestrictionLifecycleSnapshot(
            isActive: false,
            isPaused: isPaused,
            modeId: nil,
            source: .none,
            sessionId: nil
        )
    }
}

enum RestrictionLifecycleTransitionMapper {
    static func map(
        previous: RestrictionLifecycleSnapshot,
        next: RestrictionLifecycleSnapshot,
        reason: String,
        occurredAtEpochMs: Int64
    ) -> [RestrictionLifecycleEventDraft] {
        if !previous.isActive && !next.isActive {
            return []
        }

        if previous.isActive && !next.isActive {
            return event(from: previous, action: .end, reason: reason, occurredAtEpochMs: occurredAtEpochMs)
        }

        if !previous.isActive && next.isActive {
            return event(from: next, action: .start, reason: reason, occurredAtEpochMs: occurredAtEpochMs)
        }

        let modeOrSourceChanged = previous.modeId != next.modeId || previous.source != next.source || previous.sessionId != next.sessionId
        if modeOrSourceChanged {
            return event(from: previous, action: .end, reason: reason, occurredAtEpochMs: occurredAtEpochMs) +
                event(from: next, action: .start, reason: reason, occurredAtEpochMs: occurredAtEpochMs)
        }

        if !previous.isPaused && next.isPaused {
            return event(from: next, action: .pause, reason: reason, occurredAtEpochMs: occurredAtEpochMs)
        }
        if previous.isPaused && !next.isPaused {
            return event(from: next, action: .resume, reason: reason, occurredAtEpochMs: occurredAtEpochMs)
        }

        return []
    }

    private static func event(
        from snapshot: RestrictionLifecycleSnapshot,
        action: RestrictionLifecycleAction,
        reason: String,
        occurredAtEpochMs: Int64
    ) -> [RestrictionLifecycleEventDraft] {
        guard let source = RestrictionLifecycleSource(modeSource: snapshot.source) else {
            return []
        }
        let sessionId = (snapshot.sessionId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let modeId = (snapshot.modeId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sessionId.isEmpty,
              !modeId.isEmpty,
              !normalizedReason.isEmpty,
              occurredAtEpochMs > 0 else {
            return []
        }
        return [
            RestrictionLifecycleEventDraft(
                sessionId: sessionId,
                modeId: modeId,
                action: action,
                source: source,
                reason: normalizedReason,
                occurredAtEpochMs: occurredAtEpochMs
            ),
        ]
    }
}
