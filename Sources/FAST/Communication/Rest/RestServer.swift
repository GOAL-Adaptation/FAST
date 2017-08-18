/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        RESTful API to FAST
 *
 *  author: Adam Duracz
 *
 */

//---------------------------------------

import Foundation
import LoggerAPI
import PerfectLib
import PerfectHTTP
import PerfectHTTPServer

//---------------------------------------

// Key prefix for initialization
fileprivate let key = ["proteus","server","rest"]

class RestServer {

    let server = HTTPServer()
    var routes = Routes()

    @discardableResult init() {
        
        server.serverPort = initialize(type: UInt16.self, name: "port", from: key) ?? 1338

        routes.add(method: .get, uri: "/alive", handler: {
            _, response in
            response.status = Runtime.shouldTerminate ? .serviceUnavailable : .ok
            response.completed()
            }
        )

        routes.add(method: .post, uri: "/process", handler: {
            request, response in
                // FIXME Implement stub 
                Log.error("The /process endpoint has not been implemented yet.")
                response.completed() // HTTP 202
            }
        )

        routes.add(method: .post, uri: "/perturb", handler: {
            request, response in
            if let json = self.readRequestBody(request: request, fromEndpoint: "/perturb") {
                Log.debug("Received valid JSON on /perturb endpoint: \(json)")

                // FIXME Use (definitions section of) Swagger specification to validate the input,
                //       to make indexing and casts fail there instead, with detailed error information.
                let missionIntent          =        json["missionIntent"]!          as! String
                // FIXME Set scenario knobs
                let availableCores         =    Int(json["availableCores"]!         as! String)
                let availableCoreFrequency =    Int(json["availableCoreFrequency"]! as! String)
                let missionLength          =    Int(json["missionLength"]!          as! String)
                let sceneObfuscation       = Double(json["sceneObfuscation"]!       as! String)

                // Change intent
                // TODO Figure out if it is better to delay intent change/controller re-init until the end of the window
                if let intentSpec = Runtime.intentCompiler.compileIntentSpec(source: missionIntent) {
                    Runtime.reinitializeController(intentSpec)

                    // FIXME Handle scenario knobs listed in the Perturbation JSON Schema: 
                    //       availableCores, availableCoreFrequency, missionLength, sceneObfuscation. 
                    //       This requires:
                    //       1) extending the Runtime with a handler for scenario knob setting,
                    //       2) adding missionLength and sceneObfuscation knobs, perhaps to a new 
                    //          "Environment" TextApiModule.

                    response.status = .ok // HTTP 202, which is default, but setting it for clarity
                
                    Log.info("Successfully received request on /perturb REST endpoint.")
                }
                else {
                    Log.error("Could not parse intent specification from JSON payload: \(missionIntent)")    
                }
            }
            else {
                response.status = .notAcceptable // HTTP 406
            }
            response.completed()
        })

        routes.add(method: .post, uri: "/query", handler: {
            request, response in
                // FIXME Implement stub 
                Log.error("The /query endpoint has not been implemented yet.")
                response.completed() // HTTP 202
            }
        )

        routes.add(method: .post, uri: "/enable", handler: {
            _, response in
            let currentApplicationExecutionMode = Runtime.runtimeKnobs.applicationExecutionMode.get()
            switch currentApplicationExecutionMode {
                case .Adaptive:
                    Runtime.runtimeKnobs.applicationExecutionMode.set(.NonAdaptive)
                    Log.info("Successfully received request on /enable REST endpoint. Adaptation turned off.")
                case .NonAdaptive:
                    Runtime.runtimeKnobs.applicationExecutionMode.set(.Adaptive)
                    Log.info("Successfully received request on /enable REST endpoint. Adaptation turned on.")
                default:
                    Log.warning("Current application execution mode (\(currentApplicationExecutionMode)) is not one of {.Adaptive, .NonAdaptive}.")
                    Runtime.runtimeKnobs.applicationExecutionMode.set(.Adaptive)
                    Log.info("Successfully received request on /enable REST endpoint. Adaptation turned on.")
            }
            response.completed()
        })

        routes.add(method: .post, uri: "/terminate", handler: {
            _, response in
            Runtime.shouldTerminate = true
            response.completed() // HTTP 202
            }
        )

        server.addRoutes(routes)

        do {
            try server.start()
            Log.info("REST server open on port \(server.serverPort).")
        } catch PerfectError.networkError(let err, let msg) {
            Log.warning("Network error thrown while starting REST server: \(err) \(msg).")
        } catch let err {
            Log.warning("Error thrown while starting REST server: \(err).")
        }
        
    }

    func readRequestBody(request: HTTPRequest, fromEndpoint endpoint: String) -> [String : Any]? {
        if let bodyString = request.postBodyString {
            if let bodyData = bodyString.data(using: String.Encoding.utf8) {
                do {
                    let json = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
                    Log.debug("Received valid JSON on \(endpoint) endpoint: \(json)")
                    return json
                } catch let err {
                    Log.error("POST body sent to /perturb REST endpoint does not contain valid JSON: \(bodyString). \(err)")
                    return nil
                }
            } 
            else {
                Log.error("POST body sent to /perturb REST endpoint does not contain UTF8-encoded data: \(bodyString).")
                return nil
            }
        }
        else {
            Log.error("Empty POST body sent to /perturb REST endpoint.")
            return nil
        }
    }

}

