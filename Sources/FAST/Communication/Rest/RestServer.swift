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

    let contentTypeTextPlain       = "text/plain"
    let contentTypeApplicationJson = "application/json"

    unowned let runtime: Runtime

    func name() -> String? {
        return nil
    }

    let server = HTTPServer()
    var routes = Routes()
    let requestQueue : DispatchQueue

    var responses: [String: HTTPResponse] = [:]

    /**
      * Add a route that modifiers the handler to make invocations happen serially,
      * in the order that they were received.
      */
    func addSerialRoute(method: HTTPMethod, uri: String, handler: @escaping (HTTPRequest, HTTPResponse) -> Void) {
        routes.add(method: method, uri: uri) { request, response in
            self.requestQueue.async {
                let randId = UUID().uuidString
                self.responses[randId] = response
                handler(request, response)
                self.responses.removeValue(forKey: randId)
            }
        }
    }

    /** Add a JSON object as the body of the HTTPResponse parameter. */
    func addJsonBody(toResponse response: HTTPResponse, json: [String : Any], jsonDescription: String, endpointName: String) {
        let jsonString = convertToJsonSR4783(from: json)
        response.setBody(string: jsonString)
        response.setHeader(.contentType, value: contentTypeApplicationJson)
        Log.verbose("Successfully responded to request on /\(endpointName) REST endpoint: \(jsonString).")
        response.completed() // HTTP 202
    }

    @discardableResult init(port: UInt16, address: String, runtime: Runtime) {
        self.runtime = runtime
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

    func stop(error: String? = nil) {
        for (_, response) in responses {
            if let e = error {
                response.setBody(string: convertToJsonSR4783(from: ["Error": e]))
                response.status = .notAcceptable
            }
            else {
                response.setBody(string: convertToJsonSR4783(from: []))
            }
            response.setHeader(.contentType, value: contentTypeApplicationJson)
            Log.verbose("Send signal to active connections.")
            response.completed()
        }
        server.stop()
        Log.info("\(String(describing: name())) stopped (was using port \(server.serverPort)).")
    }

    func readRequestBody(request: HTTPRequest, fromEndpoint endpoint: String) -> [String : Any]? {
        if let bodyString = request.postBodyString {
            if let bodyData = bodyString.data(using: String.Encoding.utf8) {
                do {
                    let json = try JSONSerialization.jsonObject(with: bodyData) as! [String: Any]
                    Log.debug("Received valid JSON on \(endpoint) endpoint: \(json)")
                    return json
                } catch let err {
                    Log.error("POST body sent to /" + endpoint + " REST endpoint does not contain valid JSON: \(bodyString). \(err)")
                    return nil
                }
            }
            else {
                Log.error("POST body sent to /" + endpoint + " REST endpoint does not contain UTF8-encoded data: \(bodyString).")
                return nil
            }
        }
        else {
            Log.error("Empty POST body sent to /" + endpoint + " REST endpoint.")
            return nil
        }
    }

    /** Show the artihmetic AST expressed by the JSON parameter as a string. */
    static func mkExpressionString(from json: [String: Any]) -> String {

        switch json.count {
            case 1:
                // Expression wrapper
                if let expression = json["expression"] as? [String : Any] {
                    return mkExpressionString(from: expression)
                }
                // Literal Double
                if let literal = json["literal"] as? Double {
                    return "\(literal)"
                }
                // Variable name
                else if let variableName = json["variableName"] as? String {
                    return variableName
                }
                else {
                    FAST.fatalError("Unknown expression: \(json).")
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
                    FAST.fatalError("Unknown expression: \(json).")
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
                    FAST.fatalError("Unknown expression: \(json).")
                }
            default:
                FAST.fatalError("Unknown expression: \(json).")
        }

    }

    /** Show the constraint predicate AST expressed by the JSON parameter as a string. */
    static func mkPredicateString(from json: [String: Any]) -> String {
        if
            let pAny = json["predicate"],
            let p = pAny as? [String : Any]
        {
            return mkPredicateString(from: p)
        }
        guard 
            let opAny = json["operator"],
            let op = opAny as? String
        else {
            FAST.fatalError("Unable to extract operator from predicate: \(json).")
        }
        switch op {
            case "and":
                return mkPredicateString(from: json["leftPredicate"]!   as! [String: Any]) +
                       " and " +
                       mkPredicateString(from: json["rightPredicate"]!  as! [String: Any])
            default:
                return mkExpressionString(from: json["leftExpression"]!  as! [String: Any]) +
                       " " + op + " " +
                       mkExpressionString(from: json["rightExpression"]! as! [String: Any])
        }
    }

    /** Extract intent components from JSON messahge and inject them into string template. */
    static func mkIntentString(from json: [String: Any]) -> String {
        // FIXME Use (definitions section of) Swagger specification to validate the input,
        //       to make indexing and casts fail there instead, with detailed error information.

        if let missionIntentString = json["missionIntent"] as? String {
          // if missionIntent is given as the string format, we can simply use that
          return missionIntentString
        }

        let missionIntent            = json["missionIntent"]!        as! [String: Any]
        let knobs                    = missionIntent["knobs"]!       as! [[String: Any]]
        let measures                 = missionIntent["measures"]!    as! [[String: Any]]
        let intent                   = missionIntent["intent"]!      as! [String: Any]

        let intentName               = intent["name"]!               as! String
        let intentOptimizationType   = intent["optimizationType"]!   as! String
        let intentObjectiveFunction  = intent["objectiveFunction"]!  as! [String: Any]
        let intentConstraint         = intent["constraint"]!         as! [String: Any]

        let intentConstraintString = mkPredicateString(from: intentConstraint)

        let measuresString: String = measures.map {
            "\($0["name"]! as! String): Double"
        }.joined(separator:"\n\t")
        

        let knobsString: String = knobs.map {
            knob in
            let name  = knob["name"]! as! String
            let referenceValue = knob["referenceValue"]!
            let knobRange = knob["range"]! as! [Any]
            let knobRangeMap = referenceValue is String ? knobRange.map{ "\"\($0)\"" } : knobRange.map{ "\($0)" }
            let refValString = referenceValue is String ? "\"\(referenceValue)\"" : "\(referenceValue)"
            let knobRangeMapRef = knobRangeMap.map{ "\($0)" == refValString ? "\($0) reference": $0 }
            let rangeRef = knobRangeMapRef.joined(separator: ",")
            return "\(name) from [\(rangeRef)]" 
        }.joined(separator:"\n\t")
        let intentObjectiveFunctionString = mkExpressionString(from: intentObjectiveFunction)
        
        var knobConstraintsPhrase = "" 
        // missionIntent may not contain knobConstraints predicate
        if let knobConstraintsAny = missionIntent["knobConstraints"] {
            let knobConstraints = missionIntent["knobConstraints"]! as! String
            knobConstraintsPhrase =  "  such that \(knobConstraints) "
        }

        return
            "knobs \(knobsString) \n" +
             "\(knobConstraintsPhrase) \n" +
            "measures \(measuresString) \n" +
            "intent \(intentName) \(intentOptimizationType)(\(intentObjectiveFunctionString)) " +
                "such that \(intentConstraintString) \n" +
            "trainingSet []"
    }

}
