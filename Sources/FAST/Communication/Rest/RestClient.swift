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
import KituraRequest

//---------------------------------------

// Key prefix for initialization
fileprivate let key = ["proteus","client","rest"]

/** Functions for interacting with RESTful APIs */
class RestClient {

    static let serverProtocol = initialize(type: String.self, name: "serverProtocol", from: key, or: "http")
    static let serverPath     = initialize(type: String.self, name: "serverPath"    , from: key, or: "brass-th")
    static let serverPort     = initialize(type: UInt16.self, name: "serverPort"    , from: key, or: 80)

    /**
     * Successful requests with empty response bodies return `[:]`.
     * Requests that result in an error return `nil`. 
     */
    static func sendRequest
        ( to         endpoint : String
        , over       protocl  : String          = serverProtocol  
        , at         path     : String          = serverPath
        , onPort     port     : UInt16          = serverPort
        , withMethod method   : Request.Method  = .post
        , withBody   body     : [String : Any]? = nil
        , logErrors           : Bool            = true
        ) -> [String: Any]? {
        
        let urlString = "\(protocl)://\(path):\(port)/\(endpoint)"
        var request = URLRequest(url: URL(string: urlString)!)
        request.httpMethod = "\(method)"
    
        func nilAndLogError(_ message: String) -> [String: Any]? {
            if logErrors {
                Log.error(message)
            }
            return nil
        }

        var res: [String: Any]? = nil

        do {

            // If the body is nil or and empty dictionary, do not set the request body

            if body == nil || body!.isEmpty {
                Log.info("Sending \(method) request to \(urlString) with empty body.")
            }

            // Otherwise JSON-encode (as Data) the body dictionary and set the request body

            else {
                do {
                    let bodyData = try JSONSerialization.data(withJSONObject: body! as Any, options: .prettyPrinted)
                    if let bodyString = String(data: bodyData, encoding: String.Encoding.utf8) {
                        request.httpBody = bodyData
                        Log.info("Sending \(method) request to \(urlString).")
                        Log.debug("Sending \(method) request to \(urlString) with body: \(bodyString).")
                    }
                    else {
                        return nilAndLogError("Failed to UTF-encode request body data: \(body!).")
                    }
                }
                catch let jsonSerializationError {
                    return nilAndLogError("Failed to serialize request body dictionary as JSON data: \(body!). Error: \(jsonSerializationError.localizedDescription).")
                }
            }

            // Send the request

            KituraRequest.request(method, urlString).response {
                request, response, maybeResponseData, maybeError in

                // If the response decodes to a dictionary, return that, otherwise log an error and return nil

                if let responseData = maybeResponseData {
                    if let responseDataString = String(data: responseData, encoding: String.Encoding.utf8) {
                        
                        if responseDataString.isEmpty {
                            Log.verbose("Successfully received empty response from \(method) to \(path).")
                            res = [:]
                        }
                        else {
                            if let maybeResponseDataJson = try? responseDataString.jsonDecode(),
                            let responseDataJson      = maybeResponseDataJson as? [String:Any] {
                                
                                Log.verbose("Successfully JSON decoded response from \(method) to \(path): \(responseDataJson).")
                                res = responseDataJson

                            }
                            else {
                                res = nilAndLogError("Error JSON-decoding \(method) response from \(path). Error: \(maybeError).")
                            }
                        }
                        
                    }
                    else {
                        res = nilAndLogError("Error UTF8-decoding \(method) response from \(path). Error: \(maybeError).")
                    }
                } else {
                    res = nilAndLogError("Error sending \(method) request to \(path) with body: \(body). Error: \(maybeError).")
                }

            }

        }

        return res

    }

}
