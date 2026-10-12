import XCTest
@testable import RopeCore

final class InFlightWatchdogTests: XCTestCase {
    private let watchdog = InFlightWatchdog(timeoutMs: 3_000)

    func testIdleWatchdogIsNeverStalled() {
        XCTAssertFalse(watchdog.isStalled(nowMs: 100_000))
    }

    func testFrameAnsweredWithinTimeoutIsNotAStall() {
        watchdog.submitted(nowMs: 1_000)
        watchdog.answered()
        XCTAssertFalse(watchdog.isStalled(nowMs: 10_000))
    }

    func testFrameUnansweredAfterTimeoutIsAStall() {
        watchdog.submitted(nowMs: 1_000)
        XCTAssertFalse(watchdog.isStalled(nowMs: 3_999))
        XCTAssertTrue(watchdog.isStalled(nowMs: 4_001))
    }

    func testOldestUnansweredFrameDecidesTheStall() {
        watchdog.submitted(nowMs: 1_000)
        watchdog.submitted(nowMs: 3_900)
        XCTAssertTrue(watchdog.isStalled(nowMs: 4_100))
    }

    func testResetForgetsEverythingInFlight() {
        watchdog.submitted(nowMs: 1_000)
        watchdog.reset()
        XCTAssertFalse(watchdog.isStalled(nowMs: 100_000))
    }
}
