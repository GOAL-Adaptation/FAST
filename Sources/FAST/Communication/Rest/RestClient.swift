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

public enum Request {
  public enum Method: String {
    case post
    case get
  }
}

//---------------------------------------

// Key prefix for initialization
fileprivate let key = ["proteus","client","rest"]

/** Functions for interacting with RESTful APIs */
public class RestClient {

    public static let serverProtocol = initialize(type: String.self, name: "serverProtocol", from: key, or: "http")
    public static let serverAddress  = initialize(type: String.self, name: "serverAddress" , from: key, or: "127.0.0.1")
    public static let serverPort     = initialize(type: UInt16.self, name: "serverPort"    , from: key, or: 80)

    /**
     * Successful requests with empty response bodies return `[:]`.
     * Requests that result in an error return `nil`. 
     */
    public static func sendRequest
        ( to         endpoint : String
        , over       protocl  : String          = serverProtocol  
        , at         path     : String          = serverAddress
        , onPort     port     : UInt16          = serverPort
        , withMethod method   : Request.Method  = .post
        , withBody   body     : [String : Any]? = nil
        , logErrors           : Bool            = true
        ) -> [String: Any]? {
        
        let urlString = "\(protocl)://\(path):\(port)/\(endpoint)"
    
        func nilAndLogError(_ message: String) -> [String: Any]? {
            if logErrors {
                Log.error(message)
            }
            return nil
        }

        var res: [String: Any]? = nil

        if body == nil {
            Log.info("Sending \(method) request to \(urlString) with empty body.")
        }
        else {
            Log.info("Sending \(method) request to \(urlString).")
            Log.debug("Sending \(method) request to \(urlString) with body: \(body!).")
        }

        // Send the request

        guard let url = URL(string: urlString) else { return nil }
        var httpBody: Data?
        if method == .post, let body = body {
          httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpBody = httpBody
        urlRequest.httpMethod = method.rawValue
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let semaphore = DispatchSemaphore(value: 0)

        let task = URLSession.shared.dataTask(with: urlRequest) { (data, response, error) in
            guard let responseData = data else {
                res = nilAndLogError("Error sending \(method) request to \(urlString) with body: \(body ?? [:]). Error: \(error?.localizedDescription ?? "<unknown error>").")
                semaphore.signal()
                return
            }
            guard let responseDataString = String(data: responseData, encoding: String.Encoding.utf8) else {
                res = nilAndLogError("Error UTF8-decoding \(method) response from \(urlString). Error: \(error?.localizedDescription ?? "<unknown error>").")
                semaphore.signal()
                return
            }

            if responseDataString.isEmpty {
                Log.verbose("Successfully received empty response from \(method) to \(path).")
                res = [:]
            }
            else {
                if let maybeResponseDataJson = try? responseDataString.jsonDecode(),
                let responseDataJson         = maybeResponseDataJson as? [String:Any] {

                    Log.verbose("Successfully JSON decoded response from \(method) to \(urlString): \(responseDataJson).")
                    res = responseDataJson

                }
                else {
                    res = nilAndLogError("Error JSON-decoding \(method) response data from \(urlString): '\(responseDataString)'. Error: \(error?.localizedDescription ?? "<unknown error>").")
                }
            }

            semaphore.signal()
        }

        task.resume()

        _ = semaphore.wait(timeout: .distantFuture)

        return res

    }

}
