//
//  SwiftFlow.swift
//
//  Created by Jordan Wood on 11/13/23.
//

import Foundation

/// Task Priority with Aging Mechanism.
/// - Provides an enum to represent task priority with levels from veryLow to veryHigh.
/// - Supports aging, which increases the priority of a task over time.
enum TaskPriority: Int, Comparable {
    case veryLow = 0, low, medium, high, veryHigh

    /// Ages the priority, increasing it by one level, if possible.
    mutating func age() {
        guard let higherPriority = TaskPriority(rawValue: rawValue + 1) else { return }
        self = higherPriority
    }

    /// Compares two priorities.
    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}


/// Represents the result of a task execution.
/// - success: Indicates successful completion with an associated result.
/// - failure: Indicates failure with an associated error.
enum TaskResult<ResultType> {
    case success(ResultType)
    case failure(Error)
}


/// Generic errors for tasks.
enum TaskError: Error {
    case noResult
    case executionTimeout
    case cancelled
}

/// Contains metrics about task execution.
/// - waitTime: Time the task waited in the queue before execution.
/// - executionTime: Time taken for the task to execute.
/// - turnaroundTime: Total time from task creation to completion.
struct TaskMetrics {
    var waitTime: TimeInterval
    var executionTime: TimeInterval
    var turnaroundTime: TimeInterval
}

/// Builder for creating tasks with configurable properties.
class TaskBuilder<ResultType> {
    private var identifier: String = UUID().uuidString
    private var priority: TaskPriority = .medium
    private var executionBlock: (@escaping (TaskResult<ResultType>) -> Void) -> Void = { _ in }
    private var completions: [(TaskResult<ResultType>, TaskMetrics) -> Void] = []

    /// Sets the identifier for the task.
    func with(identifier: String) -> TaskBuilder {
        self.identifier = identifier
        return self
    }

    /// Sets the priority for the task.
    func with(priority: TaskPriority) -> TaskBuilder {
        self.priority = priority
        return self
    }

    /// Sets the execution block for the task.
    func with(executionBlock: @escaping (@escaping (TaskResult<ResultType>) -> Void) -> Void) -> TaskBuilder {
        self.executionBlock = executionBlock
        return self
    }

    /// Adds a completion handler to be called after task execution.
    func then(completion: @escaping (TaskResult<ResultType>, TaskMetrics) -> Void) -> TaskBuilder {
        completions.append(completion)
        return self
    }

    /// Builds and returns a new Task instance.
    func build() -> Task<ResultType> {
        return Task(identifier: identifier, priority: priority, executionBlock: executionBlock, completions: completions)
    }
}

/// Configuration for task retry and timeout.
struct TaskConfiguration {
    var maxRetries: Int = 3
    var executionTimeout: TimeInterval?

    init(maxRetries: Int = 3, executionTimeout: TimeInterval? = nil) {
        self.maxRetries = maxRetries
        self.executionTimeout = executionTimeout
    }
}

/// Represents a unified task conforming to the TaskProtocol.
class Task<ResultType>: TaskProtocol {
    let identifier: String
    var priority: TaskPriority
    let creationTime: TimeInterval
    var executionBlock: (@escaping (TaskResult<ResultType>) -> Void) -> Void
    var completions: [(TaskResult<ResultType>, TaskMetrics) -> Void]
    let executionQueue: DispatchQueue = .global()
    var isCancelled: Bool = false
    private var workItem: DispatchWorkItem?
    private var retryCount: Int = 0
    var configuration: TaskConfiguration

    /// Initializes a new task with specified properties.
    init(identifier: String, priority: TaskPriority, executionBlock: @escaping (@escaping (TaskResult<ResultType>) -> Void) -> Void, completions: [(TaskResult<ResultType>, TaskMetrics) -> Void], configuration: TaskConfiguration = TaskConfiguration()) {
        self.identifier = identifier
        self.priority = priority
        self.executionBlock = executionBlock
        self.completions = completions
        self.creationTime = ProcessInfo.processInfo.systemUptime
        self.configuration = configuration
    }
    
    /// Executes the task as part of the managed queue
    func executeInQueue(completion: @escaping () -> Void = {}) {
        guard !isCancelled else {
            completion()
            return
        }

        let startTime = ProcessInfo.processInfo.systemUptime
        let waitTime = startTime - creationTime

        workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            self.executionBlock { result in
                let endTime = ProcessInfo.processInfo.systemUptime
                self.handleCompletion(result: result, startTime: startTime, endTime: endTime, waitTime: waitTime)
                completion()
            }
        }

        guard let workItem = workItem else { return }
        executionQueue.async(execute: workItem)

        // Handle timeout
        if let executionTimeout = configuration.executionTimeout {
            executionQueue.asyncAfter(deadline: .now() + executionTimeout) { [weak self] in
                guard let self = self, !(self.workItem?.isCancelled ?? false), !self.isCancelled else { return }
                self.workItem?.cancel()
                self.handleTimeout()
                completion()
            }
        }

    }
    
    private func handleTimeout() {
        if retryCount < configuration.maxRetries {
            retryCount += 1
            executeInQueue()
        } else {
            let metrics = TaskMetrics(waitTime: 0, executionTime: configuration.executionTimeout ?? 0, turnaroundTime: configuration.executionTimeout ?? 0)
            completions.forEach { completion in
                completion(.failure(TaskError.executionTimeout), metrics)
            }
        }
    }

    private func handleCompletion(result: TaskResult<ResultType>, startTime: TimeInterval, endTime: TimeInterval, waitTime: TimeInterval) {
        let executionTime = endTime - startTime
        let turnaroundTime = endTime - self.creationTime
        let metrics = TaskMetrics(waitTime: waitTime, executionTime: executionTime, turnaroundTime: turnaroundTime)

        DispatchQueue.main.async {
            self.completions.forEach { completion in
                completion(result, metrics)
            }
        }
    }

    func cancel() {
        isCancelled = true
        workItem?.cancel()
        
        completions.forEach { completion in
            completion(.failure(TaskError.cancelled), TaskMetrics(waitTime: 0, executionTime: 0, turnaroundTime: 0))
        }
    }
    
    /// Executes the task directly.
    func execute(completion: @escaping () -> Void = {}) {
        
        let startTime = ProcessInfo.processInfo.systemUptime
        let waitTime = startTime - creationTime
        self.executionBlock { result in
            let endTime = ProcessInfo.processInfo.systemUptime
            let executionTime = endTime - startTime
            let turnaroundTime = endTime - self.creationTime
            let metrics = TaskMetrics(waitTime: waitTime, executionTime: executionTime, turnaroundTime: turnaroundTime)
            
            DispatchQueue.main.async {
                self.completions.forEach { completion in
                    completion(result, metrics)
                }
                completion()
            }
        }
    }
    

}


/// Type-erasing wrapper for tasks conforming to TaskProtocol.
/// Allows tasks of different result types to be handled uniformly.
///
protocol AnyTaskProtocol {
    var identifier: String { get }
    var priority: TaskPriority { get set }
    var creationTime: TimeInterval { get }
    func execute(completion: @escaping () -> Void)
}

/// Protocol defining essential properties of a task.
protocol TaskProtocol {
    var identifier: String { get }
    var priority: TaskPriority { get set }
    var creationTime: TimeInterval { get }
    var isCancelled: Bool { get set }
    func cancel()
    func executeInQueue(completion: @escaping () -> Void)
}

class AnyTask: AnyTaskProtocol {
    private let _identifier: String
    private var _priority: TaskPriority
    private let _creationTime: TimeInterval
    private let _execute: (@escaping () -> Void) -> Void
    private var _isCancelled: Bool = false
    private let _cancel: () -> Void
    
    var isCancelled: Bool {
        get { _isCancelled }
        set { _isCancelled = newValue }
    }

    var identifier: String { _identifier }
    var priority: TaskPriority {
        get { _priority }
        set { _priority = newValue }
    }
    var creationTime: TimeInterval { _creationTime }

    /// Initializes a new AnyTask wrapping a TaskProtocol instance.
    init<T: TaskProtocol>(_ task: T) {
        _identifier = task.identifier
        _priority = task.priority
        _creationTime = task.creationTime
        _execute = task.executeInQueue
        _cancel = task.cancel
    }

    /// Executes the wrapped task.
    func execute(completion: @escaping () -> Void) {
        guard !isCancelled else {
            completion()
            return
        }
        _execute(completion)
    }
    func cancel() {
        _isCancelled = true
        _cancel()
    }
}


/// A priority queue that manages tasks based on their priority.
/// Utilizes a simple array to store tasks and sorts them after each insertion.
struct PriorityQueue<Element: AnyTaskProtocol> {
    var elements: [Element] = []

    /// Adds a new element to the queue and re-sorts to maintain priority order.
    mutating func enqueue(_ element: Element) {
        elements.append(element)
        elements.sort(by: { $0.priority > $1.priority })
    }

    /// Removes and returns the highest priority element from the queue, if available.
    mutating func dequeue() -> Element? {
        elements.isEmpty ? nil : elements.removeFirst()
    }

    /// Updates the priority of a specific task and re-sorts the queue.
    mutating func updatePriority(for identifier: String, to newPriority: TaskPriority) {
        if let index = elements.firstIndex(where: { $0.identifier == identifier }) {
            elements[index].priority = newPriority
            elements.sort(by: { $0.priority > $1.priority })
        }
    }
}

/// The core task manager that handles task execution, priority, and concurrency.
class SwiftFlow {
    static let shared = SwiftFlow()
    private var taskQueue = PriorityQueue<AnyTask>()
    private var activeTasks = Set<String>()
    private var listeners = [String: [(TaskResult<Any>) -> Void]]()
    private var taskPerformanceRecords = [TimeInterval]()
    private let taskQueueLock = DispatchQueue(label: "com.swiftflow.lock")
    private var activeTaskCount = 0
    private var maxConcurrentTasks: Int
    private let performanceCheckInterval: TimeInterval = 10
    private var lastPerformanceCheck: TimeInterval = ProcessInfo.processInfo.systemUptime
    private var concurrencyAdjustmentHistory: [Int] = []
    private var idealCompletionTime: TimeInterval = 0.5
    private let successRateThreshold: Double = 0.80
    private var agingThreshold: TimeInterval = 10 // Age threshold for increasing priority


    /// Initializes the task manager with default settings.
    init() {
        self.maxConcurrentTasks = ProcessInfo.processInfo.activeProcessorCount
    }

    /// Adds a task to the queue and triggers its processing.
    func addTask<ResultType>(_ task: Task<ResultType>) {
        taskQueueLock.async {
            self.ageAndReorderTasks()
            let anyTask = AnyTask(task)
            self.taskQueue.enqueue(anyTask)
            self.processNextTask()
        }
    }

    /// Updates the priority of a task and reorders the queue accordingly.
    func updatePriority<ResultType: TaskProtocol>(of task: ResultType, to newPriority: TaskPriority) {
        taskQueueLock.async {
            self.taskQueue.updatePriority(for: task.identifier, to: newPriority)
        }
    }

    /// Registers a listener for task completion events.
    func addListener(for identifier: String, listener: @escaping (TaskResult<Any>) -> Void) {
        taskQueueLock.async {
            if self.listeners[identifier] == nil {
                self.listeners[identifier] = []
            }
            self.listeners[identifier]?.append(listener)
        }
    }

    /// Processes the next task in the queue if concurrency limits allow.
    private func processNextTask() {
        taskQueueLock.async { [weak self] in
            guard let self = self else { return }

            self.checkPerformanceAndAdjustConcurrency()

            if self.activeTaskCount >= self.maxConcurrentTasks {
                return
            }

            guard let task = self.taskQueue.dequeue() else { return }
            guard !self.activeTasks.contains(task.identifier) else {
                self.taskQueue.enqueue(task)
                return
            }

            self.activeTasks.insert(task.identifier)
            self.activeTaskCount += 1

            // Execute the task outside the lock to avoid deadlocks
            task.execute {
                self.taskQueueLock.async {
                    self.activeTaskCount -= 1
                    self.activeTasks.remove(task.identifier)
                    self.notifyListeners(for: task.identifier, with: .success(()))
                    self.processNextTask()
                }
            }
        }
    }

    
    /// Cancels a task by its identifier.
   func cancelTask(with identifier: String) {
       taskQueueLock.async {
           // Cancel the task in the queue
           if let index = self.taskQueue.elements.firstIndex(where: { $0.identifier == identifier }) {
               self.taskQueue.elements[index].cancel()
           }
           
           // Cancel the task if it's active
           if self.activeTasks.contains(identifier) {
               // TODO: Implement logic to cancel an active task
               self.activeTasks.remove(identifier)
           }
       }
   }

    /// Notifies registered listeners about the completion of a task.
    private func notifyListeners(for identifier: String, with result: TaskResult<Any>) {
        listeners[identifier]?.forEach { listener in
            listener(result)
        }
    }

    /// Records the performance of a task to inform future concurrency adjustments.
    private func recordTaskPerformance(_ turnaroundTime: TimeInterval) {
        taskPerformanceRecords.append(turnaroundTime)
    }

    /// Checks task performance and adjusts concurrency settings if needed.
    private func checkPerformanceAndAdjustConcurrency() {
        let currentTime = ProcessInfo.processInfo.systemUptime
        if currentTime - lastPerformanceCheck > performanceCheckInterval {
            lastPerformanceCheck = currentTime
            adjustConcurrencyBasedOnPerformance()
        }
    }

    /// Adjusts concurrency settings based on recent task performance.
    private func adjustConcurrencyBasedOnPerformance() {
        guard !taskPerformanceRecords.isEmpty else { return }

        let successRate = taskPerformanceRecords.filter { $0 <= idealCompletionTime }.count / taskPerformanceRecords.count
        taskPerformanceRecords.removeAll()

        if Double(successRate) > successRateThreshold {
            idealCompletionTime = min(idealCompletionTime + 0.1, 5)
            maxConcurrentTasks = min(ProcessInfo.processInfo.activeProcessorCount, maxConcurrentTasks + 1)
        } else {
            idealCompletionTime = max(idealCompletionTime - 0.1, 1)
            maxConcurrentTasks = max(1, maxConcurrentTasks - 1)
        }

        concurrencyAdjustmentHistory.append(maxConcurrentTasks)
    }
    
    /// Ages tasks that have been in the queue longer than the threshold and reorders them.
    private func ageAndReorderTasks() {
        let currentTime = ProcessInfo.processInfo.systemUptime
        var didAgeAnyTask = false
        for index in self.taskQueue.elements.indices {
            let task = self.taskQueue.elements[index]
            if currentTime - task.creationTime > self.agingThreshold {
                self.taskQueue.elements[index].priority.age()
                didAgeAnyTask = true
            }
        }
        if didAgeAnyTask {
            self.taskQueue.elements.sort(by: { $0.priority > $1.priority })
        }
    }
    
    /// Prints the current state of the task queue for debugging purposes.
    func debugPrintQueueStatus() {
        taskQueueLock.async {
            print("========SwiftFlow Debug========")
            print("Current Max Concurrent Tasks: \(self.maxConcurrentTasks)")
            print("Task Queue (In Order):")
            var i = 0
            for task in self.taskQueue.elements {
                print("#\(i) - Task ID: \(task.identifier), Priority: \(task.priority)")
                i += 1
            }
            print("\nConcurrency Adjustment History: \(self.concurrencyAdjustmentHistory)")
            print("===============================")
        }
    }
}
