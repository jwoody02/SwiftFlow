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
// Create a network task with a unique identifier, give it medium priority
// Tasks can be given different priority levels depending on their importance
// more important tasks will be placed ahead of lower priority tasks

let networkTask = Task<String>(identifier: "networkRequest", priority: .medium) { completion in
    // Asynchronous network request
    someNetworkRequest { result, error in
        if let error = error {
            completion(.failure(error))
        } else if let result = result {
            completion(.success(result))
        } else {
            completion(.failure(TaskError.noResult))
        }
    }
}

// Handle task completion
networkTask.then { result, metrics in
    // this will be called when the task is done, do what you want with the result of the code, or keep track of metrics to optimize in the future.
    switch result {
    case .success(let data):
        print("Data: \(data)")
    case .failure(let error):
        print("Error: \(error)")
    }
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
    func executeExample() {
        // Example usage of SwiftFlow with HTTP request tasks
        
        // 1. Define the HTTP request task
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
        
        // 2. Add tasks to SwiftFlow
        let urls = [
            "https://api.publicapis.org/entries",      // Public APIs list
            "https://api.agify.io/?name=bella",        // Age prediction
            "https://api.genderize.io/?name=lucy",     // Gender prediction
            "https://api.nationalize.io/?name=nathaniel", // Nationality prediction
            "https://catfact.ninja/fact",              // Random cat facts
            "https://dog.ceo/api/breeds/image/random", // Random dog images
            "https://api.coinpaprika.com/v1/tickers",  // Cryptocurrency tickers
            "https://api.coindesk.com/v1/bpi/currentprice.json", // Bitcoin Price Index
            "https://api.quotable.io/random",          // Random quotes
            "https://api.zippopotam.us/us/90210",      // US Zip Code Lookup
            "https://pokeapi.co/api/v2/pokemon/ditto", // Pokémon information
            "https://api.funtranslations.com/translate/yoda.json?text=Master+Yoda", // Fun translations
            // Add more as needed
        ]
        urls.forEach { urlString in
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
![Diagram](documentation/concurrencyprocess.png)

## License
SwiftFlow is released under the MIT License. Feel free to use it for whatever you want!



