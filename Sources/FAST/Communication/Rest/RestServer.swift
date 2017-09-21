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

    private let utcDateFormatter = DateFormatter()

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

        utcDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        utcDateFormatter.timeZone = TimeZone(identifier: "GMT")

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
                
                func toArrayOfPairDicts(_ dict: [String : Any]) -> [[String : Any]] {
                    return Array(dict).map { (s , a) in [s : a] }
                }

                func unwrapValues(_ dict: [String: Any]) -> [String: Any] {
                    return Dictionary(dict.map { (s,a) in (s, (a as! [String: Any])["value"]!) })
                }

                func extractStatus(from module: TextApiModule) -> [String : Any] {
                    return (module.getStatus() as? [String: Any]).map{ unwrapValues($0) } ?? [:]
                }

                func extractStatus(of subModule: String, from module: TextApiModule?) -> [String : Any] {
                    return (module?.getStatus()?[subModule] as? [String: Any]).map{ unwrapValues($0) } ?? [:]
                }

                if let runningTime               = Runtime.getMeasure("runningTime"),
                   let energy                    = Runtime.getMeasure("energy"),
                   let numberOfProcessedInputs   = Runtime.getMeasure("iteration") {

                    let architecture             = Runtime.architecture?.name ?? "NOT CONFIGURED"
                    let systemConfigurationKnobs = extractStatus(of: "systemConfigurationKnobs", from: Runtime.architecture ) 
                    let applicationKnobs         = extractStatus(of: "applicationKnobs",         from: Runtime.application  )
                    let scenarioKnobs            = extractStatus(                                from: Runtime.scenarioKnobs)

                    let status : [String : Any] =
                        [ "time"      : self.utcDateFormatter.string(from: Date())
                        , "arguments" : 
                            [ "architecture"             : architecture
                            , "runningTime"              : runningTime
                            , "energy"                   : energy
                            , "numberOfProcessedInputs"  : numberOfProcessedInputs
                            , "applicationKnobs"         : toArrayOfPairDicts(applicationKnobs)
                            , "systemConfigurationKnobs" : toArrayOfPairDicts(systemConfigurationKnobs)
                            , "scenarioKnobs"            : toArrayOfPairDicts(scenarioKnobs)
                            , "measures"                 : toArrayOfPairDicts(Runtime.getMeasures())
                            ]
                        ]

                    do {
                        let statusData = try JSONSerialization.data(withJSONObject: status)
                        if let statusString = String(data: statusData, encoding: String.Encoding.utf8) {
                            response.setBody(string: statusString)
                            Log.info("Successfully responded to request on /query REST endpoint: \(statusString).")
                            response.completed() // HTTP 202
                        }
                        else {
                            response.status = .notAcceptable // HTTP 406
                            Log.info("Error while UTF8-encoding JSON status in response to request on /query REST endpoint: \(status).")                        
                        }
                    } 
                    catch let e {
                        response.status = .notAcceptable // HTTP 406
                        Log.info("Exception while serializing JSON in response to request on /query REST endpoint: \(status). Exception: \(e).")
                    }
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

