import Flutter
import UIKit
import XCTest
import Foundation


@testable import pauza_screen_time

// This demonstrates a simple unit test of the Swift portion of this plugin's implementation.
//
// See https://developer.apple.com/documentation/xctest for more information about using XCTest.

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

  func testLifecycleQueue_appendAndFetchWindowOrder() {
    let drafts = [
      makeDraft(seq: 1),
      makeDraft(seq: 2),
      makeDraft(seq: 3),
    ]
    assertStoreSuccess(RestrictionStateStore.appendLifecycleEvents(drafts))

    let pending = RestrictionStateStore.loadPendingLifecycleEvents(limit: 2)

    XCTAssertEqual(2, pending.count)
    XCTAssertEqual(eventId(seq: 1, occurredAt: 1), pending[0].id)
    XCTAssertEqual(eventId(seq: 2, occurredAt: 2), pending[1].id)
  }

  func testLifecycleQueue_ackInclusiveAdvancesCursor() {
    let drafts = (1...3).map { makeDraft(seq: Int64($0)) }
    assertStoreSuccess(RestrictionStateStore.appendLifecycleEvents(drafts))

    assertStoreSuccess(
      RestrictionStateStore.ackLifecycleEvents(throughEventId: eventId(seq: 1, occurredAt: 1))
    )
    let pending = RestrictionStateStore.loadPendingLifecycleEvents(limit: 10)

    XCTAssertEqual(2, pending.count)
    XCTAssertEqual(eventId(seq: 2, occurredAt: 2), pending[0].id)
    XCTAssertEqual(eventId(seq: 3, occurredAt: 3), pending[1].id)
  }

  func testLifecycleQueue_ackBeyondTailDrainsQueue() {
    let drafts = (1...3).map { makeDraft(seq: Int64($0)) }
    assertStoreSuccess(RestrictionStateStore.appendLifecycleEvents(drafts))

    assertStoreSuccess(
      RestrictionStateStore.ackLifecycleEvents(
        throughEventId: "00000000000000001000-0000000000000"
      )
    )

    XCTAssertTrue(RestrictionStateStore.loadPendingLifecycleEvents(limit: 10).isEmpty)
  }

  func testLifecycleQueue_capPrunesOldestLogically() {
    let drafts = (1...10_002).map { makeDraft(seq: Int64($0)) }
    assertStoreSuccess(RestrictionStateStore.appendLifecycleEvents(drafts))

    let first = RestrictionStateStore.loadPendingLifecycleEvents(limit: 1).first
    XCTAssertEqual(eventId(seq: 3, occurredAt: 3), first?.id)
  }

  func testLifecycleQueue_malformedStoredRecordIsSkipped() {
    let drafts = (1...3).map { makeDraft(seq: Int64($0)) }
    assertStoreSuccess(RestrictionStateStore.appendLifecycleEvents(drafts))
    testDefaults.set(["id": "bad"], forKey: eventStorageKey(seq: 2))

    let pending = RestrictionStateStore.loadPendingLifecycleEvents(limit: 3)

    XCTAssertEqual(2, pending.count)
    XCTAssertEqual(eventId(seq: 1, occurredAt: 1), pending[0].id)
    XCTAssertEqual(eventId(seq: 3, occurredAt: 3), pending[1].id)
  }

  func testLifecycleQueue_ackPerformsBoundedGc() {
    let drafts = (1...5).map { makeDraft(seq: Int64($0)) }
    assertStoreSuccess(RestrictionStateStore.appendLifecycleEvents(drafts))
    XCTAssertNotNil(testDefaults.object(forKey: eventStorageKey(seq: 1)))
    XCTAssertNotNil(testDefaults.object(forKey: eventStorageKey(seq: 2)))

    assertStoreSuccess(
      RestrictionStateStore.ackLifecycleEvents(throughEventId: eventId(seq: 3, occurredAt: 3))
    )

    XCTAssertNil(testDefaults.object(forKey: eventStorageKey(seq: 1)))
    XCTAssertNil(testDefaults.object(forKey: eventStorageKey(seq: 2)))
    XCTAssertNil(testDefaults.object(forKey: eventStorageKey(seq: 3)))
    XCTAssertNotNil(testDefaults.object(forKey: eventStorageKey(seq: 4)))
  }

  private func makeDraft(seq: Int64) -> RestrictionLifecycleEventDraft {
    RestrictionLifecycleEventDraft(
      sessionId: "s1",
      modeId: "focus",
      action: .start,
      source: .manual,
      reason: "test_\(seq)",
      occurredAtEpochMs: seq
    )
  }

  private func eventId(seq: Int64, occurredAt: Int64) -> String {
    "\(formatCounter(seq, width: 20))-\(formatCounter(occurredAt, width: 13))"
  }

  private func eventStorageKey(seq: Int64) -> String {
    "lifecycleEvent.\(formatCounter(seq, width: 20))"
  }

  private func formatCounter(_ value: Int64, width: Int) -> String {
    String(value).leftPadding(toLength: width, withPad: "0")
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

private extension String {
  func leftPadding(toLength length: Int, withPad pad: String) -> String {
    guard count < length else { return self }
    return String(repeating: pad, count: length - count) + self
  }
}
