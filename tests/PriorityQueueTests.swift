//
//  PriorityQueueTests.swift
//  SwiftFlowTests
//
//  Created by Jordan Wood on 11/15/23.
//

import XCTest
@testable import HUF

class PriorityQueueTests: XCTestCase {

    var queue: PriorityQueue<AnyTask>!

    override func setUpWithError() throws {
        queue = PriorityQueue<AnyTask>()
    }

    func testPriorityQueueOrdering() {
        let lowPriorityTask = AnyTask(Task<String>(identifier: "low", priority: .low, executionBlock: { _ in }, completions: []))
        let highPriorityTask = AnyTask(Task<String>(identifier: "high", priority: .high, executionBlock: { _ in }, completions: []))
        
        queue.enqueue(lowPriorityTask)
        queue.enqueue(highPriorityTask)

        XCTAssertEqual(queue.dequeue()?.identifier, "high", "High priority task should be dequeued first.")
        XCTAssertEqual(queue.dequeue()?.identifier, "low", "Low priority task should be dequeued second.")
    }

}
