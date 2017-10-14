/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Generic RestServer methods
 *
 *  author: Adam Duracz
 *
 */

//---------------------------------------

import Foundation
import Dispatch
import LoggerAPI
import KituraRequest
import PerfectLib
import PerfectHTTP
import PerfectHTTPServer

//---------------------------------------

// Key prefix for initialization
fileprivate let key = ["proteus","server","rest"]

/** Blocks until endpoint responds. */
func waitUntilUp(endpoint: String, host: String, port: UInt16, method: Request.Method, description: String, body: [String : Any] = [:]) {

    var response: [String: Any]? = nil
    var backoff: UInt32 = 100 // backoff delay in ms

    while response == nil {
        response =
            RestClient.sendRequest( to         : endpoint
                                  , over       : "http"
                                  , at         : host
                                  , onPort     : port
                                  , withMethod : method
                                  , withBody   : body
                                  , logErrors  : false
                                  )
        Log.verbose("Wait \(backoff) ms before checking if \(description) server is open on port \(RestClient.serverPort) \(Request.Method.get).")
        usleep(backoff * 1000) // wait before checking if REST server is up again
        backoff *= 2
    }

    Log.info("\(description) server open on port \(RestClient.serverPort).")

}

/** Blocks until endpoint stops responding. */
func waitUntilDown(endpoint: String, host: String, port: UInt16, method: Request.Method, description: String, body: [String : Any] = [:]) {

    var response: [String: Any]? = nil
    var backoff: UInt32 = 100 // backoff delay in ms

    while response != nil {
        response =
            RestClient.sendRequest( to         : endpoint
                                  , over       : "http"
                                  , at         : host
                                  , onPort     : port
                                  , withMethod : method
                                  , withBody   : body
                                  , logErrors  : false
                                  )
        Log.verbose("Wait \(backoff) ms before checking if \(description) server is down on port \(RestClient.serverPort) \(Request.Method.get).")
        usleep(backoff * 1000) // wait before checking if REST server is down again
        backoff *= 2
    }

    Log.info("\(description) server down (was on port \(RestClient.serverPort)).")

}

public class RestServer {

    func name() -> String? {
        return nil
    }

    let server = HTTPServer()
    var routes = Routes()
    let requestQueue : DispatchQueue

    /** 
      * Add a route that modifiers the handler to make invocations happen serially, 
      * in the order that they were received. 
      */
    func addSerialRoute(method: HTTPMethod, uri: String, handler: @escaping (HTTPRequest, HTTPResponse) -> Void) {
        routes.add(method: method, uri: uri, 
            handler: { request, response in self.requestQueue.async { handler(request, response) } }
        )
    }

    /** Add a JSON object as the body of the HTTPResponse parameter. */
    func addJsonBody(toResponse response: HTTPResponse, json: [String : Any], jsonDescription: String, endpointName: String) {
        do {
            let jsonString = convertToJsonSR4783(from: json)
            response.setBody(string: jsonString)
            Log.verbose("Successfully responded to request on /\(endpointName) REST endpoint: \(jsonString).")
            response.completed() // HTTP 202

        } 
        catch let e {
            response.status = .notAcceptable // HTTP 406
            Log.error("Exception while serializing JSON in response to request on /\(endpointName) REST endpoint: \(json). Exception: \(e).")
        }
    }

    @discardableResult init(port: UInt16, address: String) {

        self.requestQueue = DispatchQueue(label: "requestQueueAtPort\(port)") // A serial queue
        server.serverAddress = address
        server.serverPort = port
        
    }

    func start() {
        do {
            try server.start()
            Log.info("\(String(describing: name())) open on port \(server.serverPort).")
        } catch PerfectError.networkError(let err, let msg) {
            Log.error("Network error thrown while starting \(String(describing: name())) on port \(server.serverPort): \(err) \(msg).")
        } catch let err {
            Log.error("Error thrown while starting \(String(describing: name())) on port \(server.serverPort): \(err).")
        }
    }

    func stop() {
        do {
            try server.stop()
            Log.info("\(String(describing: name())) stopped (was using port \(server.serverPort)).")
        } catch PerfectError.networkError(let err, let msg) {
            Log.error("Network error thrown while stopping \(String(describing: name())) (on port \(server.serverPort)): \(err) \(msg).")
        } catch let err {
            Log.error("Error thrown while stopping \(String(describing: name())) (on port \(server.serverPort)): \(err).")
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

    /** Show the artihmetic AST expressed by the JSON parameter as a string. */
    static func mkExpressionString(from json: [String: Any]) -> String {

        switch json.count {
            case 1:
                // Literal Double
                if let literal = json["literal"] as? Double {
                    return "\(literal)"
                }
                // Variable name
                else if let variableName = json["variableName"] as? String {
                    return variableName
                }
                else {
                    fatalError("Unknown expression: \(json).")
                }
            case 2:
                // Unary operator
                if let op = json["operator"],
                   let e = json["expression"],
                   let expression = e as? [String: Any] {
                    let eString = mkExpressionString(from: expression)
                    return "(\(op)\(eString))"
                }
                else {
                    fatalError("Unknown expression: \(json).")
                }
            case 3:
                // Binary operator
                if let opAny = json["operator"],
                   let op = opAny as? String,
                   ["+","-","*","/"].contains(op),
                   let l = json["leftExpression"],
                   let r = json["rightExpression"],
                   let lExpression = l as? [String: Any],
                   let rExpression = r as? [String: Any] {
                    let lString = mkExpressionString(from: lExpression)
                    let rString = mkExpressionString(from: rExpression)
                    return "(\(lString) \(op) \(rString))"
                }
                else {
                    fatalError("Unknown expression: \(json).")
                }
            default:
                fatalError("Unknown expression: \(json).")
        }

    }

    /** Extract intent components from JSON messahge and inject them into string template. */
    static func mkIntentString(from json: [String: Any]) -> String {
        // FIXME Use (definitions section of) Swagger specification to validate the input,
        //       to make indexing and casts fail there instead, with detailed error information.

        let missionIntent           = json["missionIntent"]!        as! [String: Any]
        let knobs                   = missionIntent["knobs"]!       as! [[String: Any]]
        let measures                = missionIntent["measures"]!    as! [[String: Any]]
        let intent                  = missionIntent["intent"]!      as! [String: Any]

        let intentName              = intent["name"]!               as! String
        let intentOptimizationType  = intent["optimizationType"]!   as! String
        let intentObjectiveFunction = intent["objectiveFunction"]!  as! [String: Any]
        let intentConstraintMeasure = intent["constraintMeasure"]!  as! String
        let intentConstraintValue   = intent["constraintValue"]!    as! Double

        let measuresString: String = measures.map { 
            "\($0["name"]! as! String): Double" 
        }.joined(separator:"\n\t")

        let knobsString: String = knobs.map {
            knob in
            let name  = knob["name"]! as! String
            let range = (knob["range"]! as! [Any]).map{ "\($0)" }.joined(separator: ",")
            let referenceValue = knob["referenceValue"]!
            return "\(name) = [\(range)] reference \(referenceValue)" 
        }.joined(separator:"\n\t")

        let intentObjectiveFunctionString = mkExpressionString(from: intentObjectiveFunction)

        return 
            "knobs \(knobsString) \n" +
            "measures \(measuresString) \n" +
            "intent \(intentName) \(intentOptimizationType)(\(intentObjectiveFunctionString)) " +
                "such that \(intentConstraintMeasure) == \(intentConstraintValue) \n" +
            "trainingSet []"
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

