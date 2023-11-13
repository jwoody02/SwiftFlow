//
//  SwiftFlow.swift
//
//  Created by Jordan Wood on 11/13/23.
//

import Foundation

// Task Priority with Aging Mechanism
enum TaskPriority: Int, Comparable {
    case veryLow = 0, low, medium, high, veryHigh
    
    mutating func age() {
        if self.rawValue < TaskPriority.veryHigh.rawValue {
            self = TaskPriority(rawValue: self.rawValue + 1)!
        }
    }
    
    static func < (lhs: TaskPriority, rhs: TaskPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// Task Result
enum TaskResult<ResultType> {
    case success(ResultType)
    case failure(Error)
}

// Generic Error for Non-Error Results
enum TaskError: Error {
    case noResult
    case executionTimeout
}

// Task Metrics
struct TaskMetrics {
    var waitTime: TimeInterval
    var executionTime: TimeInterval
    var turnaroundTime: TimeInterval
}

// Task Protocol
protocol TaskProtocol {
    var identifier: String { get }
    var priority: TaskPriority { get set }
    var creationTime: TimeInterval { get }
    func execute(completion: @escaping () -> Void)
}

// Unified Task
class Task<ResultType>: TaskProtocol {
    let identifier: String
    var priority: TaskPriority
    let creationTime: TimeInterval
    var executionBlock: (@escaping (TaskResult<ResultType>) -> Void) -> Void
    var completion: ((TaskResult<ResultType>, TaskMetrics) -> Void)?
    let executionQueue: DispatchQueue
    
    init(identifier: String, priority: TaskPriority, executionQueue: DispatchQueue = .global(), executionBlock: @escaping (@escaping (TaskResult<ResultType>) -> Void) -> Void) {
        self.identifier = identifier
        self.priority = priority
        self.executionBlock = executionBlock
        self.executionQueue = executionQueue
        self.creationTime = ProcessInfo.processInfo.systemUptime
    }
    
    func then(completion: @escaping (TaskResult<ResultType>, TaskMetrics) -> Void) -> Task {
        self.completion = completion
        return self
    }
    
    func execute(completion: @escaping () -> Void) {
        let startTime = ProcessInfo.processInfo.systemUptime
        let waitTime = startTime - creationTime
        
        executionQueue.async { [weak self] in
            guard let self = self else { return }
            self.executionBlock { result in
                let endTime = ProcessInfo.processInfo.systemUptime
                let executionTime = endTime - startTime
                let turnaroundTime = endTime - self.creationTime
                
                let metrics = TaskMetrics(waitTime: waitTime, executionTime: executionTime, turnaroundTime: turnaroundTime)
                
                DispatchQueue.main.async {
                    self.completion?(result, metrics)
                    completion()
                }
            }
        }
    }
}

protocol AnyTaskProtocol {
    var identifier: String { get }
    var priority: TaskPriority { get set }
    var creationTime: TimeInterval { get }
    func execute(completion: @escaping () -> Void)
}

class AnyTask: AnyTaskProtocol {
    private let _identifier: String
    private var _priority: TaskPriority
    private let _creationTime: TimeInterval
    private let _execute: (@escaping () -> Void) -> Void

    var identifier: String { _identifier }
    var priority: TaskPriority {
        get { _priority }
        set { _priority = newValue }
    }
    var creationTime: TimeInterval { _creationTime }

    init<T: TaskProtocol>(_ task: T) {
        _identifier = task.identifier
        _priority = task.priority
        _creationTime = task.creationTime
        _execute = task.execute
    }

    func execute(completion: @escaping () -> Void) {
        _execute(completion)
    }
}


// Priority Queue
struct PriorityQueue<Element: AnyTaskProtocol> {
    var elements: [Element] = []
    
    mutating func enqueue(_ element: Element) {
        elements.append(element)
        elements.sort(by: { $0.priority > $1.priority })
    }
    
    mutating func dequeue() -> Element? {
        elements.isEmpty ? nil : elements.removeFirst()
    }
    
    mutating func updatePriority(for identifier: String, to newPriority: TaskPriority) {
        if let index = elements.firstIndex(where: { $0.identifier == identifier }) {
            elements[index].priority = newPriority
            elements.sort(by: { $0.priority > $1.priority })
        }
    }
}

// Task Manager
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
    private var idealCompletionTime: TimeInterval = 2.0
    private let successRateThreshold: Double = 0.80
    
    init() {
        self.maxConcurrentTasks = UserDefaults.standard.integer(forKey: "maxConcurrentTasks")
        if self.maxConcurrentTasks == 0 {
            self.maxConcurrentTasks = ProcessInfo.processInfo.activeProcessorCount
        }
    }
    
    func addTask<ResultType>(_ task: Task<ResultType>) {
            taskQueueLock.async {
                let anyTask = AnyTask(task)
                self.taskQueue.enqueue(anyTask)
                self.processNextTask()
            }
        }
    
    func updatePriority<ResultType: TaskProtocol>(of task: ResultType, to newPriority: TaskPriority) {
        taskQueueLock.async {
            self.taskQueue.updatePriority(for: task.identifier, to: newPriority)
        }
    }
    
    func addListener(for identifier: String, listener: @escaping (TaskResult<Any>) -> Void) {
        taskQueueLock.async {
            if self.listeners[identifier] == nil {
                self.listeners[identifier] = []
            }
            self.listeners[identifier]?.append(listener)
        }
    }
    
    private func processNextTask() {
        taskQueueLock.async {
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
            
            task.execute {
                let endTime = ProcessInfo.processInfo.systemUptime
                self.recordTaskPerformance(endTime - task.creationTime)
                
                self.taskQueueLock.async {
                    self.activeTaskCount -= 1
                    self.activeTasks.remove(task.identifier)
                    self.processNextTask()
                }
            }
        }
    }
    
    private func notifyListeners(for identifier: String, with result: TaskResult<Any>) {
        listeners[identifier]?.forEach { listener in
            listener(result)
        }
    }
    
    private func recordTaskPerformance(_ turnaroundTime: TimeInterval) {
        taskPerformanceRecords.append(turnaroundTime)
    }
    
    private func checkPerformanceAndAdjustConcurrency() {
        let currentTime = ProcessInfo.processInfo.systemUptime
        if currentTime - lastPerformanceCheck > performanceCheckInterval {
            lastPerformanceCheck = currentTime
            adjustConcurrencyBasedOnPerformance()
        }
    }
    
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
        UserDefaults.standard.set(maxConcurrentTasks, forKey: "maxConcurrentTasks")
    }
    
    func debugPrintQueueStatus() {
        taskQueueLock.sync {
            print("========SwiftFlow Debug========")
            print("Current Max Concurrent Tasks: \(maxConcurrentTasks)")
            print("Task Queue (In Order):")
            var i = 0
            for task in taskQueue.elements {
                print("#\(i) - Task ID: \(task.identifier), Priority: \(task.priority)")
                i += 1
            }
            print("\nConcurrency Adjustment History: \(concurrencyAdjustmentHistory)")
            print("===============================")
        }
    }
}


