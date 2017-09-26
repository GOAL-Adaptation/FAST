/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Extensions to built-in SWIFT types: URLSession
 *
 *  authors: Adam Duracz
 */

//---------------------------------------

import Foundation
import Dispatch

//---------------------------------------

extension URLSession {
    
    func synchronousDataTask(urlRequest: URLRequest) -> (Data?, URLResponse?, Error?) {
    
        var data: Data?
        var response: URLResponse?
        var error: Error?

        let semaphore = DispatchSemaphore(value: 0)

        let dataTask = self.dataTask(with: urlRequest) {
            data = $0
            response = $1
            error = $2

            semaphore.signal()
        }
        dataTask.resume()

        _ = semaphore.wait(timeout: .distantFuture)

        return (data, response, error)

    }
}