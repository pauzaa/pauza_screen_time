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

  private func assertStoreSuccess(_ result: RestrictionStateStore.StoreResult) {
    switch result {
    case .success:
      return
    case .appGroupUnavailable(let resolvedGroupId):
      XCTFail("App Group unavailable: \(resolvedGroupId)")
    }
  }
}
