/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        REST client
 *
 *  author: Adam Duracz
 *
 */

//---------------------------------------

import Foundation
import LoggerAPI
import PerfectLib

//---------------------------------------

// Key prefix for initialization
fileprivate let key = ["proteus","client","rest"]

/** Functions for interacting with RESTful APIs */
class RestClient {

    static let serverProtocol = initialize(type: String.self, name: "serverProtocol", from: key, or: "http")
    static let serverPath     = initialize(type: String.self, name: "serverPath"    , from: key, or: "brass-th")
    static let serverPort     = initialize(type: String.self, name: "serverPort"    , from: key, or: "80")

    static func postJsonRequest(to endpoint: String, at path: String = testHarnessPath, withBody body: [String: Any]) -> [String: Any]? {
        
        var request = URLRequest(url: URL(string: "\(serverProtocol)://\(serverPath):\(serverPort)/\(endpoint)")!)
        request.httpMethod = "POST"
    
        do {

            let jsonString = try JSONSerialization.data(withJSONObject: body, options: .prettyPrinted)
            request.httpBody = jsonString
            
            let session = URLSession.shared
            let (maybeData, response, maybeError) = session.synchronousDataTask(urlRequest: request)

            if let data = maybeData {
                if let dataString = String(data: data, encoding: String.Encoding.utf8) {
                    if let maybeDataJson = try? dataString.jsonDecode(),
                       let dataJson = maybeDataJson as? [String:Any] {
                        
                        Log.verbose("Successfully received response from POST to \(path): \(dataString).")
                        return dataJson

                    }
                    else {
                        Log.error("Error JSON-decoding POST response from \(path). Error: \(maybeError).")
                        return [:]
                    }
                }
                else {
                    Log.error("Error UTF8-decoding POST response from \(path). Error: \(maybeError).")
                    return [:]
                }
            } else {
                Log.error("Error sending POST request to \(path) with body: \(jsonString). Error: \(maybeError).")
                return [:]
            }
            Log.info("Sent POST request to \(path) with body: \(jsonString).")

        } catch let jsonSerializationError {
            Log.error("Failed to serialize data to JSON: \(body). Error: \(jsonSerializationError.localizedDescription).")
            return [:]
        }

    }

}
