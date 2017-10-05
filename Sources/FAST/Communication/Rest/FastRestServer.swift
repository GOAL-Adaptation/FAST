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
import Dispatch
import LoggerAPI
import PerfectLib
import PerfectHTTP
import PerfectHTTPServer

//---------------------------------------

// Key prefix for initialization
fileprivate let key = ["proteus","server","rest"]

class FastRestServer : RestServer {

    override func name() -> String? {
        return "REST server"
    }

    @discardableResult override init(port: UInt16) {

        super.init(port: port)

        routes.add(method: .get, uri: "/alive", handler: {
            _, response in
            response.status = Runtime.shouldTerminate ? .serviceUnavailable : .ok
            response.completed()
            }
        )

        addSerialRoute(method: .post, uri: "/process", handler: {
            request, response in
            if let json = self.readRequestBody(request: request, fromEndpoint: "/process") {

                if let n = json["inputs"],
                   let numberOfInputsToProcess = n as? Int {
                    Log.debug("Received JSON on /process endpoint: \(json)")
                    Runtime.process(numberOfInputs: UInt64(numberOfInputsToProcess))
                    Log.info("Processed \(numberOfInputsToProcess) input(s).")
                }
                else {                    
                    Log.error("Failed to extract number of inputs to process from JSON: \(json).")
                    response.status = .notAcceptable // HTTP 406
                }

            }
            else {
                response.status = .notAcceptable // HTTP 406
            }
            response.completed()
        })

        addSerialRoute(method: .post, uri: "/perturb", handler: {
            request, response in
            if let json = self.readRequestBody(request: request, fromEndpoint: "/perturb") {
                Log.debug("Received valid JSON on /perturb endpoint: \(json)")

                let missionIntentString = RestServer.mkIntentString(from: json)

                // FIXME Set scenario knobs listed in the Perturbation JSON Schema: 
                //       availableCores, availableCoreFrequency, missionLength, sceneObfuscation. 
                //       This requires:
                //       1) extending the Runtime with a handler for scenario knob setting,
                //       2) adding missionLength and sceneObfuscation knobs, perhaps to a new 
                //          "Environment" TextApiModule.
                let availableCores         =    Int(json["availableCores"]!         as! Int32)
                let availableCoreFrequency =    Int(json["availableCoreFrequency"]! as! Int64)
                let missionLength          =    Int(json["missionLength"]!          as! Int64)
                let sceneObfuscation       = Double(json["sceneObfuscation"]!       as! Double)
            
                response.status = self.changeIntent(missionIntentString, accumulatedStatus: response.status)
            }
            else {
                response.status = .notAcceptable // HTTP 406
            }
            response.completed()
        })

        routes.add(method: .get, uri: "/query", handler: {
            request, response in

                if let runtimeStatus = Runtime.statusDictionary() {
                    self.addJsonBody(toResponse: response, json: runtimeStatus, jsonDescription: "status", endpointName: "query")
                }
                else {
                    response.status = .notAcceptable // HTTP 406
                    Log.info("Error while extracting status in response to request on /query REST endpoint.")
                }

            }
        )

        addSerialRoute(method: .post, uri: "/enable", handler: {
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

        routes.add(method: .post, uri: "/changeIntent", handler: {
            request, response in
                if let json = self.readRequestBody(request: request, fromEndpoint: "/perturb") {
                    Log.debug("Received valid JSON on /perturb endpoint: \(json)")
                    let missionIntent = json["missionIntent"]! as! String
                    response.status = self.changeIntent(missionIntent, accumulatedStatus: response.status)
                    Log.info("Intent change requested through /changeIntent endpoint.")
                }
                else {
                    Log.error("Did not receive valid JSON on /perturb endpoint: \(request)")
                }
                response.completed()
            }
        )

        routes.add(method: .post, uri: "/terminate", handler: {
            _, response in
            Runtime.shouldTerminate = true
            Log.info("Application termination requested through /terminate endpoint.")
            response.completed() // HTTP 202
            }
        )

        server.addRoutes(routes)
        
    }

}

