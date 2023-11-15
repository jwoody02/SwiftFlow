//
//  TaskTests.swift
//  SwiftFlowTests
//
//  Created by Jordan Wood on 11/15/23.
//

import XCTest
@testable import HUF

class TaskTests: XCTestCase {

    func testTaskExecutionSuccess() {
        let executionExpectation = expectation(description: "TaskExecuted")
        let task = Task<String>(identifier: "testTask", priority: .medium, executionBlock: { completion in
            completion(.success("Success"))
        }, completions: [{ result, _ in
            if case .success(let value) = result {
                XCTAssertEqual(value, "Success", "The execution block should return a success with 'Success'.")
                executionExpectation.fulfill()
            }
        }])

        task.execute()
        waitForExpectations(timeout: 1)
    }

    func testTaskCancellation() {
        let task = Task<String>(identifier: "cancelTask", priority: .medium, executionBlock: { completion in
            completion(.success("Executed"))
        }, completions: [{ result, _ in
            if case .failure(let error) = result, case TaskError.cancelled = error {
                return // Expected path
            }
            XCTFail("Task should be cancelled and not executed.")
        }])

        task.cancel()
        XCTAssert(task.isCancelled, "Task should be marked as cancelled.")
    }

}
