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
    static let serverAddress  = initialize(type: String.self, name: "serverAddress" , from: key, or: "127.0.0.1")
    static let serverPort     = initialize(type: UInt16.self, name: "serverPort"    , from: key, or: 80)

    /**
     * Successful requests with empty response bodies return `[:]`.
     * Requests that result in an error return `nil`. 
     */
    static func sendRequest
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

        do {

            if body == nil || body!.isEmpty {
                Log.info("Sending \(method) request to \(urlString) with empty body.")
            }
            else {
                Log.info("Sending \(method) request to \(urlString).")
                Log.debug("Sending \(method) request to \(urlString) with body: \(body!).")
            }

            // Send the request

            /** 
             *  Custom JSON encoding, used in place of the built-in KituraRequest JSONEncoding,
             *  to work around https://bugs.swift.org/browse/SR-4783.
             */
            struct SR4783WorkAroundJSONEncoding: Encoding {
                public static let `default` = SR4783WorkAroundJSONEncoding()
                public func encode(_ request: inout URLRequest, parameters: Request.Parameters?) throws {
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    guard let parameters = parameters, !parameters.isEmpty else { return }
                    request.httpBody = convertToJsonSR4783(from: parameters).data(using: .utf8)
                }
            }

            KituraRequest.request(method, urlString, parameters: body, encoding: SR4783WorkAroundJSONEncoding.default).response {
                _, response, maybeResponseData, maybeError in

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
                                res = nilAndLogError("Error JSON-decoding \(method) response from \(path). Error: \(String(describing: maybeError)).")
                            }
                        }
                        
                    }
                    else {
                        res = nilAndLogError("Error UTF8-decoding \(method) response from \(path). Error: \(String(describing: maybeError)).")
                    }
                } else {
                    res = nilAndLogError("Error sending \(method) request to \(path) with body: \(body). Error: \(String(describing: maybeError)).")
                }

            }

        }

        return res

    }

}
