//
//  TaskPriorityTests.swift
//  SwiftFlowTests
//
//  Created by Jordan Wood on 11/15/23.
//

import XCTest
@testable import CHANGE_THIS

class TaskPriorityTests: XCTestCase {

    func testPriorityAging() {
        var priority = TaskPriority.low
        priority.age()
        XCTAssertEqual(priority, .medium, "Aging a low priority should result in a medium priority.")
    }

    func testPriorityAgingAtMax() {
        var priority = TaskPriority.veryHigh
        priority.age()
        XCTAssertEqual(priority, .veryHigh, "Aging a veryHigh priority should remain at veryHigh.")
    }

    func testPriorityComparison() {
        XCTAssertTrue(TaskPriority.low < TaskPriority.high, "Low priority should be less than high priority.")
    }

}

