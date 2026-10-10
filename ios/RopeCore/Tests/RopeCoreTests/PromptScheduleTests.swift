import XCTest
@testable import RopeCore

final class PromptScheduleTests: XCTestCase {
    func testCheerEveryTen() {
        XCTAssertEqual(PromptSchedule.prompt(before: 9, after: 10), .cheer)
        XCTAssertEqual(PromptSchedule.prompt(before: 85, after: 95), .cheer)
    }

    func testBravoEveryHundredTakesPrecedence() {
        XCTAssertEqual(PromptSchedule.prompt(before: 99, after: 100), .bravo)
    }

    func testNothingBetweenMilestones() {
        XCTAssertNil(PromptSchedule.prompt(before: 0, after: 0))
        XCTAssertNil(PromptSchedule.prompt(before: 11, after: 12))
    }
}
