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

            if let executionTimeout = self.configuration.executionTimeout {
                DispatchQueue.global().asyncAfter(deadline: .now() + executionTimeout) {
                    self.workItem?.cancel()
                    let errorResult: TaskResult<ResultType> = .failure(TaskError.executionTimeout)
                    self.handleCompletion(result: errorResult, startTime: startTime, endTime: ProcessInfo.processInfo.systemUptime, waitTime: waitTime)
                    completion()
                }
            }
        }

        // execute work item
        guard let workItem = workItem else { return }
        executionQueue.async(execute: workItem)

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
        self.isCancelled = true
        self.workItem?.cancel()

        // Notify of cancellation
        let metrics = TaskMetrics(waitTime: 0, executionTime: 0, turnaroundTime: 0)
        self.completions.forEach { completion in
            completion(.failure(TaskError.cancelled), metrics)
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

/// enum for the different load levels that can be specified by user
enum LoadLevel {
    case low, medium, high
}

/// customizable configuration for max CPU load level, memory level, setting the max concurrent tasks, and using dynamic scheduling
struct SwiftFlowConfiguration {
    var cpuLoadLevel: LoadLevel = .medium
    var memoryLoadLevel: LoadLevel = .medium
    var manualMaxConcurrentTasks: Int? = nil
    var useDynamicTaskScheduling: Bool = true

    func loadFactor(for level: LoadLevel) -> Double {
        switch level {
        case .low:
            return 0.3 // 30%
        case .medium:
            return 0.5 // 50%
        case .high:
            return 0.7 // 70%
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
    private var agingThreshold: TimeInterval = 10 // Age threshold for increasing priority
    
    var configuration = SwiftFlowConfiguration()
    private var systemLoadManager = SystemLoadManager()


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
                
            // find next task to execute, making sure to block duplicate tasks
            while let task = self.taskQueue.dequeue() {
                if !self.activeTasks.contains(task.identifier) {
                    self.activeTasks.insert(task.identifier)
                    self.activeTaskCount += 1

                    task.execute {
                        self.taskQueueLock.async {
                            self.activeTaskCount -= 1
                            self.activeTasks.remove(task.identifier)
                            self.notifyListeners(for: task.identifier, with: .success(()))
                            self.processNextTask()
                        }
                    }
                    break
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
        taskQueueLock.async {
            self.listeners[identifier]?.forEach { listener in
                listener(result)
            }
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
    
    
    /// Updates the configuration (called by user)
    func updateConfiguration(_ newConfiguration: SwiftFlowConfiguration) {
        taskQueueLock.async {
            self.configuration = newConfiguration
        }
    }
    
    /// Adjusts concurrency settings based on recent task performance.
    private func adjustConcurrencyBasedOnPerformance() {
        /// If user has disabled dynamic task scheduling, exit
        guard configuration.useDynamicTaskScheduling else {
            self.maxConcurrentTasks = configuration.manualMaxConcurrentTasks ?? ProcessInfo.processInfo.activeProcessorCount
            return
        }
        
        /// check current cpu and memory load, adjust the maximum concurrent tasks accordingly
        let currentCpuLoad = systemLoadManager.getCurrentCpuLoad()
        let currentMemoryLoad = systemLoadManager.getCurrentMemoryLoad()
        let cpuLoadFactor = configuration.loadFactor(for: configuration.cpuLoadLevel)
        let memoryLoadFactor = configuration.loadFactor(for: configuration.memoryLoadLevel)

        taskQueueLock.async {
            if currentCpuLoad < cpuLoadFactor && currentMemoryLoad < memoryLoadFactor {
                /// increase allowed concurrent tasks, with a hard limit of active processor count to avoid thread explosions
                self.maxConcurrentTasks = min(ProcessInfo.processInfo.activeProcessorCount, self.maxConcurrentTasks + 1)
            } else {
                /// we've exceeded our threshold, reduce number of concurrent tasks
                self.maxConcurrentTasks = max(1, self.maxConcurrentTasks - 1)
            }
        }
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
            print("===============================")
        }
    }
}

/// Provides useful information about current CPU and Memory load
class SystemLoadManager {
    /// Returns value from 0.0 to 1.0 (0 to 100%)  that represents the relative CPU load
    func getCurrentCpuLoad() -> Double {
        var load: Double = 0.0
        var numCpuU = natural_t(0)
        var cpuInfo: processor_info_array_t?
        var numCpuInfo = mach_msg_type_number_t(0)

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &numCpuU, &cpuInfo, &numCpuInfo)
        if result == KERN_SUCCESS, let cpuInfo = cpuInfo {
            for i in 0 ..< Int(numCpuU) {
                let offset = Int(CPU_STATE_MAX) * i
                let inUse = cpuInfo[offset + Int(CPU_STATE_USER)] + cpuInfo[offset + Int(CPU_STATE_SYSTEM)] + cpuInfo[offset + Int(CPU_STATE_NICE)]
                let total = inUse + cpuInfo[offset + Int(CPU_STATE_IDLE)]
                load += (Double(inUse) / Double(total))
            }
            load /= Double(numCpuU)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(numCpuInfo) * vm_size_t(MemoryLayout<Int32>.stride))
        }
        return load
    }
    
    /// Returns value from 0.0 to 1.0 (0 to 100%) that represents the relative Memory load
    func getCurrentMemoryLoad() -> Double {
        var load: Double = 0.0
        var vmStats = vm_statistics64()
        var infoCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(infoCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &infoCount)
            }
        }
        if result == KERN_SUCCESS {
            let totalUsedMemory = vmStats.active_count + vmStats.inactive_count + vmStats.wire_count
            let totalMemory = vmStats.active_count + vmStats.inactive_count + vmStats.free_count + vmStats.wire_count
            load = Double(totalUsedMemory) / Double(totalMemory)
        }
        return load
    }
}
