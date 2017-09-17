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

class RestServer {

    let server = HTTPServer()
    var routes = Routes()
    var requestQueue = DispatchQueue(label: "requestQueue") // A serial queue

    /** 
      * Add a route that modifiers the handler to make invocations happen serially, 
      * in the order that they were received. 
      */
    func addSerialRoute(method: HTTPMethod, uri: String, handler: @escaping (HTTPRequest, HTTPResponse) -> Void) {
        routes.add(method: method, uri: uri, 
            handler: { request, response in self.requestQueue.async { handler(request, response) } }
        )
    }

    @discardableResult init() {

        server.serverPort = initialize(type: UInt16.self, name: "port", from: key) ?? 1338

        routes.add(method: .get, uri: "/alive", handler: {
            _, response in
            response.status = Runtime.shouldTerminate ? .serviceUnavailable : .ok
            response.completed()
            }
        )

        addSerialRoute(method: .post, uri: "/process", handler: {
            request, response in
                // FIXME Implement stub 
                Log.error("The /process endpoint has not been implemented yet.")
                response.completed() // HTTP 202
            }
        )

        addSerialRoute(method: .post, uri: "/perturb", handler: {
            request, response in
            if let json = self.readRequestBody(request: request, fromEndpoint: "/perturb") {
                Log.debug("Received valid JSON on /perturb endpoint: \(json)")

                // FIXME Use (definitions section of) Swagger specification to validate the input,
                //       to make indexing and casts fail there instead, with detailed error information.

                // Extract intent components from JSON messahge and inject them into string template

                let missionIntent           = json["missionIntent"]!        as! [String: Any]
                let knobs                   = missionIntent["knobs"]!       as! [[String: Any]]
                let measures                = missionIntent["measures"]!    as! [[String: Any]]
                let intent                  = missionIntent["intent"]!      as! [String: Any]

                let intentName              = intent["name"]!               as! String
                let intentOptimizationType  = intent["optimizationType"]!   as! String
                let intentObjectiveFunction = intent["objectiveFunction"]!  as! String
                let intentConstraintMeasure = intent["constraintMeasure"]!  as! String
                let intentConstraintValue   = intent["constraintValue"]!    as! Double

                let measuresString: String = measures.map { 
                    "\($0["name"]! as! String): Double" 
                }.joined(separator:"\n\t")

                let knobsString: String = knobs.map {
                    knob in
                    let name  = knob["name"]! as! String
                    let range = (knob["range"]! as! [Any]).map{ "\($0)" }.joined(separator: ",")
                    let referenceValue = knob["referenceValue"]! as! Double
                    return "\(name) = [\(range)] reference \(referenceValue)" 
                }.joined(separator:"\n\t")

                let missionIntentString =
                    "knobs \(knobsString) \n" +
                    "measures \(measuresString) \n" +
                    "intent \(intentName) \(intentOptimizationType)(\(intentObjectiveFunction)) such that \(intentConstraintMeasure) == \(intentConstraintValue) \n" +
                    "trainingSet []"

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

        routes.add(method: .post, uri: "/query", handler: {
            request, response in
                // FIXME Implement stub 
                Log.error("The /query endpoint has not been implemented yet.")
                response.completed() // HTTP 202
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

    /** Change the active intent */
    func changeIntent(_ missionIntent: String, accumulatedStatus: HTTPResponseStatus) -> HTTPResponseStatus {
        if let intentSpec = Runtime.intentCompiler.compileIntentSpec(source: missionIntent) {
            // TODO Figure out if it is better to delay intent change/controller re-init until the end of the window
            Runtime.reinitializeController(intentSpec)
            Log.info("Successfully received request on /perturb REST endpoint.")
            return accumulatedStatus
        }
        else {
            Log.error("Could not parse intent specification from JSON payload: \(missionIntent)")    
            return .notAcceptable
        }
    }

}

