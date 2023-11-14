# SwiftFlow

![SwiftFlow Logo](documentation/swiftflowLogo.png)

SwiftFlow is an advanced task management system for Swift, designed to handle concurrent tasks with dynamic performance adjustment efficiently. It uses an adaptive algorithm to optimize task execution based on system load and task performance, ensuring smooth and efficient task handling.

## Features

- Dynamic concurrency adjustment based on task completion times.
- Task prioritization with aging mechanism.
- Customizable task execution blocks.
- Performance metrics tracking for each task.

## Installation

Clone the SwiftFlow repository:

```bash
git clone https://github.com/yourusername/SwiftFlow.git
```
copy `SwiftFlow.swift` from the Sources folder into your project. That's it!

# Usage
## Creating a Task
To create a task, define the task execution block and initialize a `Task` object:
```swift
// define a task. Make note: You should define what kind of objects will be passed back into the completion callback
// in this example, you'd replace {return_type} with a list of the actual types of objects you want to pass into the "then" block further down
let task = Task<{return_type}>(identifier: {give the task a unique string identifier), priority: {priority}) { completion in
    // Any code you put here will run whenever this task executes
    // to indicate completion of the task, please use the Result object and call completion(.success()) or .error
}

// define what should happen after a task completes
task.then { result, metrics in
    // this will be called when the task is done, do what you want with the result of the code, or keep track of metrics to optimize in the future.
    switch result {
    case .success(let data):
        // keep in mind data will be the return type defined when you made the task
    case .failure(let error):
        print("Error: \(error)")
    }
    // get information on how quickly the task executed
    print("Execution Time: \(metrics.executionTime)")
}
```

PLEASE NOTE: simply creating a task will not add it to the task queue. All that we've done in the above example is define the code for a certain task, and what should be done upon its completion. To actually execute a task, use the `addTask` function as shown in the section below.

## Executing a Task
Add your task to the TaskManager for execution:
```swift
SwiftFlow.shared.addTask(networkTask)
```
Tasks can be defined anywhere, all it takes is this one line to add the task to the queue and execute it again. Keep in mind, the task's `then` completion block will be called, you can update this completion block dynamically anywhere in your code as can be seen in the previous section `Creating a Task`.

# Detailed Example
To give an example of how useful SwiftFlow is, lets use it to execute a large number of http requests concurrently. I'm going to define a simple class to help us make requests with the default shared URLSession and a completion callback:
```swift

// Simple class to make requests and return the responses as a Result via a escaping completion
class HTTPClient {
    static func makeRequest(to urlString: String, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: urlString) else {
            completion(.failure(URLError(.badURL)))
            return
        }

        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data, let responseString = String(data: data, encoding: .utf8) else {
                completion(.failure(URLError(.cannotParseResponse)))
                return
            }

            completion(.success(responseString))
        }

        task.resume()
    }
}

class ExampleClass() {
    // 1. Define the HTTP request task
    // This is an example of how you can create functions that help programmatically define tasks
    // In this example, this function creates a http request task and can easily be used to create an infinite number of new HTTP tasks
    func createHTTPRequestTask(urlString: String, priority: TaskPriority) -> Task<Result<String, Error>> {
        let task = Task<Result<String, Error>>(identifier: UUID().uuidString, priority: priority) { completion in
            HTTPClient.makeRequest(to: urlString) { result in
                completion(.success(result))
            }
        }
    
        // Handle the task completion
        task.then { result, metrics in
            switch result {
            case .success(let response):
                print("Success: \(response)")
            case .failure(let error):
                print("Error: \(error.localizedDescription)")
            }
            print("Task Metrics: Wait Time: \(metrics.waitTime), Execution Time: \(metrics.executionTime)")
        }
    
        return task
    }


    func executeExample() {
        // Example usage of SwiftFlow with HTTP request tasks

        // 2. Add tasks to SwiftFlow
        let urls = [
            "https://api.publicapis.org/entries",      // Public APIs list
            "https://api.agify.io/?name=bella",        // Age prediction
            // Add more as needed
        ]
        urls.forEach { urlString in
            // create a task for each url in the array and add the task to the queue
            let httpRequestTask = createHTTPRequestTask(urlString: urlString, priority: .medium)
            SwiftFlow.shared.addTask(httpRequestTask)
        }
        
        // Optional: Debug print the queue status
        SwiftFlow.shared.debugPrintQueueStatus()

}
}
```

# Concurrency Adjustment Mechanism
SwiftFlow adjusts the concurrency level (aka the number of tasks that can run at once) based on the performance of tasks. The system calculates an ideal completion time for tasks and adjusts it based on the success rate of task completion.

## How It Works
 - Initial Ideal Time: Set to a default value (e.g., 2 seconds).
 - Success Rate Calculation: The percentage of tasks completing within the ideal time is calculated.
 - Adjusting Ideal Time:
   - The ideal time is increased if the success rate is above a threshold (e.g., 80%).
   - If the success rate is below the threshold, the ideal time is decreased.
 - Concurrency Adjustment:
   - Increase concurrency if the success rate is high. Aka: allow more tasks to run at once.
   - Decrease concurrency if the success rate is low. Aka: decrease the amount of allowed tasks at once
  
Below is an example diagram of how the mechanism works, looking at the red line that indicates what percent of objects (represented as 0.0 to 1.0, where 1.0 is 100%, 0.8 is 80% etc), as the number of tasks that complete in the target time increases, then that means we can allow more tasks to execute concurrently without slowing down the application:
![Diagram](documentation/concurrencyprocess.png)

## License
SwiftFlow is released under the MIT License. Feel free to use it for whatever you want!



