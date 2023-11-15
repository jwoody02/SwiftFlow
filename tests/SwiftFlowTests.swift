//
//  SwiftFlowTests.swift
//  SwiftFlowTests
//
//  Created by Jordan Wood on 11/15/23.
//

import XCTest
@testable import HUF

class SwiftFlowTests: XCTestCase {

    var swiftFlow: SwiftFlow!

    override func setUpWithError() throws {
        swiftFlow = SwiftFlow()
    }

    func testAddAndExecuteTask() {
        let executionExpectation = expectation(description: "TaskExecuted")
        let task = Task<String>(identifier: "swiftFlowTest", priority: .medium, executionBlock: { completion in
            completion(.success("Executed"))
        }, completions: [{ result, _ in
            if case .success(let value) = result {
                XCTAssertEqual(value, "Executed", "Task should execute with 'Executed' result.")
                executionExpectation.fulfill()
            }
        }])

        swiftFlow.addTask(task)
        waitForExpectations(timeout: 1)
    }

    // TODO: - Additional tests for priority update, task cancellation, listener notification...
}

