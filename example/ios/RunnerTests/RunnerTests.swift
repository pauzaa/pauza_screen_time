import Flutter
import UIKit
import XCTest

@testable import pauza_screen_time

class RunnerTests: XCTestCase {
  private var testSuiteName: String!
  private var testDefaults: UserDefaults!

  override func setUp() {
    super.setUp()
    testSuiteName = "group.com.example.pauza_screen_time.tests.\(UUID().uuidString)"
    AppGroupStore.updateGroupIdentifier(testSuiteName)
    testDefaults = UserDefaults(suiteName: testSuiteName)
    testDefaults.removePersistentDomain(forName: testSuiteName)
  }

  override func tearDown() {
    testDefaults?.removePersistentDomain(forName: testSuiteName)
    AppGroupStore.updateGroupIdentifier(nil)
    testDefaults = nil
    testSuiteName = nil
    super.tearDown()
  }

  func testGetPlatformVersion() {
    let plugin = PauzaScreenTimePlugin()

    let call = FlutterMethodCall(methodName: "getPlatformVersion", arguments: [])

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertEqual(result as! String, "iOS " + UIDevice.current.systemVersion)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testLifecycleQueueLegacySemantics_appendFetchAck() {
    let drafts = [
      RestrictionLifecycleEventDraft(
        sessionId: "s1",
        modeId: "focus",
        action: .start,
        source: .manual,
        reason: "test_1",
        occurredAtEpochMs: 1
      ),
      RestrictionLifecycleEventDraft(
        sessionId: "s1",
        modeId: "focus",
        action: .pause,
        source: .manual,
        reason: "test_2",
        occurredAtEpochMs: 2
      ),
    ]
    assertStoreSuccess(RestrictionStateStore.appendLifecycleEvents(drafts))

    let pending = RestrictionStateStore.loadPendingLifecycleEvents(limit: 2)
    XCTAssertEqual(2, pending.count)

    assertStoreSuccess(
      RestrictionStateStore.ackLifecycleEvents(throughEventId: pending.first!.id)
    )
    let remaining = RestrictionStateStore.loadPendingLifecycleEvents(limit: 10)
    XCTAssertEqual(1, remaining.count)
    XCTAssertEqual(.pause, remaining.first?.action)
  }

  func testAppendLifecycleEvents_assignsUniqueMonotonicIdsAndAdvancesSequence() {
    let initialDrafts = [
      RestrictionLifecycleEventDraft(
        sessionId: "s1",
        modeId: "focus",
        action: .start,
        source: .manual,
        reason: "batch_1",
        occurredAtEpochMs: 1
      ),
      RestrictionLifecycleEventDraft(
        sessionId: "s1",
        modeId: "focus",
        action: .pause,
        source: .manual,
        reason: "batch_2",
        occurredAtEpochMs: 2
      ),
      RestrictionLifecycleEventDraft(
        sessionId: "s1",
        modeId: "focus",
        action: .resume,
        source: .manual,
        reason: "batch_3",
        occurredAtEpochMs: 3
      ),
    ]
    assertStoreSuccess(RestrictionStateStore.appendLifecycleEvents(initialDrafts))

    let initialEvents = RestrictionStateStore.loadPendingLifecycleEvents(limit: 10)
    XCTAssertEqual(3, initialEvents.count)
    let initialIds = initialEvents.map(\.id)
    XCTAssertEqual(initialIds.count, Set(initialIds).count)
    XCTAssertEqual(initialIds, initialIds.sorted())

    XCTAssertEqual(3, sequenceValue(forKey: RestrictionStateStore.lifecycleEventSeqKey))

    let nextDrafts = [
      RestrictionLifecycleEventDraft(
        sessionId: "s1",
        modeId: "focus",
        action: .pause,
        source: .manual,
        reason: "batch_4",
        occurredAtEpochMs: 4
      ),
    ]
    assertStoreSuccess(RestrictionStateStore.appendLifecycleEvents(nextDrafts))

    let allEvents = RestrictionStateStore.loadPendingLifecycleEvents(limit: 10)
    XCTAssertEqual(4, allEvents.count)
    let allIds = allEvents.map(\.id)
    XCTAssertEqual(allIds.count, Set(allIds).count)
    XCTAssertEqual(allIds, allIds.sorted())
    XCTAssertTrue(allIds.last! > initialIds.last!)

    XCTAssertEqual(4, sequenceValue(forKey: RestrictionStateStore.lifecycleEventSeqKey))
  }

  func testLifecycleHandlerGetPending_returnsOnMainThread() {
    let handler = RestrictionsMethodHandler()
    let drafts = [
      RestrictionLifecycleEventDraft(
        sessionId: "s1",
        modeId: "focus",
        action: .start,
        source: .manual,
        reason: "test",
        occurredAtEpochMs: 1
      ),
    ]
    assertStoreSuccess(RestrictionStateStore.appendLifecycleEvents(drafts))

    let call = FlutterMethodCall(
      methodName: MethodNames.getPendingLifecycleEvents,
      arguments: ["limit": 10]
    )
    let resultExpectation = expectation(description: "get pending returns")
    handler.handle(call) { result in
      XCTAssertTrue(Thread.isMainThread)
      let payload = result as? [[String: Any]]
      XCTAssertNotNil(payload)
      XCTAssertEqual(1, payload?.count)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 2)
  }

  func testLifecycleHandlerAck_returnsOnMainThread() {
    let handler = RestrictionsMethodHandler()
    let drafts = [
      RestrictionLifecycleEventDraft(
        sessionId: "s1",
        modeId: "focus",
        action: .start,
        source: .manual,
        reason: "test",
        occurredAtEpochMs: 1
      ),
    ]
    assertStoreSuccess(RestrictionStateStore.appendLifecycleEvents(drafts))
    let throughId = RestrictionStateStore.loadPendingLifecycleEvents(limit: 1).first!.id

    let call = FlutterMethodCall(
      methodName: MethodNames.ackLifecycleEvents,
      arguments: ["throughEventId": throughId]
    )
    let resultExpectation = expectation(description: "ack returns")
    handler.handle(call) { result in
      XCTAssertTrue(Thread.isMainThread)
      XCTAssertNil(result)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 2)
  }

  func testLoadActiveSession_corruptData_throwsAndClears() {
    testDefaults.set(["invalid": "data"], forKey: RestrictionStateStore.activeSessionKey)

    XCTAssertThrowsError(try RestrictionStateStore.loadActiveSession()) { error in
      guard let decodeError = error as? RestrictionStateStore.StorageDecodeError else {
        XCTFail("Expected StorageDecodeError but got \(error)")
        return
      }
      XCTAssertTrue(decodeError.message.contains("missing modeId or blockedAppIds"))
    }

    let remaining = testDefaults.dictionary(forKey: RestrictionStateStore.activeSessionKey)
    XCTAssertNil(remaining, "Active session should be cleared after corrupt load")

    XCTAssertNoThrow(try RestrictionStateStore.loadActiveSession())
    XCTAssertNil(try RestrictionStateStore.loadActiveSession())
  }

  func testAppendLifecycleEvents_corruptData_clearsAndAppends() {
    testDefaults.set("[{corrupt}]", forKey: RestrictionStateStore.lifecycleEventsKey)
    
    let drafts = [
      RestrictionLifecycleEventDraft(
        sessionId: "s1",
        modeId: "focus",
        action: .start,
        source: .manual,
        reason: "test",
        occurredAtEpochMs: 1
      )
    ]

    RestrictionStateStore.appendLifecycleEvents(drafts)

    let events = testDefaults.array(forKey: RestrictionStateStore.lifecycleEventsKey) as? [[String: Any]] ?? []
    // It should have reset the corrupt array and appended 1 new event
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events.first?["reason"] as? String, "test")
  }

  func testDecodeTokens_corruptBase64_appendsToInvalidTokens() {
    if #available(iOS 16.0, *) {
      let manager = ShieldManager.shared
      let corruptTokens = ["invalid_base64_!@#", "vfvfvf=="]
      
      let result = manager.decodeTokens(base64Tokens: corruptTokens)
      
      XCTAssertTrue(result.tokens.isEmpty)
      XCTAssertTrue(result.appliedBase64Tokens.isEmpty)
      XCTAssertEqual(result.invalidTokens.count, 2)
      XCTAssertEqual(result.invalidTokens, corruptTokens)
    }
  }

  private func assertStoreSuccess(_ result: RestrictionStateStore.StoreResult) {
    switch result {
    case .success:
      return
    case .appGroupUnavailable(let resolvedGroupId):
      XCTFail("App Group unavailable: \(resolvedGroupId)")
    }
  }

  private func sequenceValue(forKey key: String) -> Int64 {
    if let number = testDefaults.object(forKey: key) as? NSNumber {
      return number.int64Value
    }
    if let raw = testDefaults.object(forKey: key) as? Int64 {
      return raw
    }
    if let raw = testDefaults.object(forKey: key) as? Int {
      return Int64(raw)
    }
    return 0
  }
}
