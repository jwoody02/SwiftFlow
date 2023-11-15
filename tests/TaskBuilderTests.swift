//
//  TaskBuilderTests.swift
//  SwiftFlowTests
//
//  Created by Jordan Wood on 11/15/23.
//

import XCTest
@testable import HUF

class TaskBuilderTests: XCTestCase {

    var builder: TaskBuilder<String>!

    override func setUpWithError() throws {
        builder = TaskBuilder<String>()
    }

    func testTaskBuilderWithCustomIdentifier() {
        let task = builder.with(identifier: "CustomID").build()
        XCTAssertEqual(task.identifier, "CustomID", "The task should have the custom identifier.")
    }

    func testTaskBuilderWithExecutionBlock() {
        let executionExpectation = expectation(description: "ExecutionBlock")
        let task = builder.with(executionBlock: { completion in
            completion(.success("Executed"))
            executionExpectation.fulfill()
        }).build()

        task.execute()

        waitForExpectations(timeout: 1) { error in
            XCTAssertNil(error, "The execution block should be called without errors.")
        }
    }

    func testTaskBuilderWithPriority() {
        let task = builder.with(priority: .high).build()
        XCTAssertEqual(task.priority, .high, "The task should have high priority.")
    }

}
