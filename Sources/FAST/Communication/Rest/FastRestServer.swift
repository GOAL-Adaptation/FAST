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

    @discardableResult override init(port: UInt16, address: String, runtime: Runtime) {

        super.init(port: port, address: address, runtime: runtime)

        routes.add(method: .get, uri: "/alive", handler: {
            _, response in
            response.status = runtime.shouldTerminate ? .serviceUnavailable : .ok
            self.addJsonBody(toResponse: response, json: [:], jsonDescription: "empty", endpointName: "alive")
            }
        )

        addSerialRoute(method: .post, uri: "/process", handler: {
            request, response in
            if let json = self.readRequestBody(request: request, fromEndpoint: "/process") {

                if let n = json["inputs"],
                   let numberOfInputs = n as? Int {
                    Log.debug("Received JSON on /process endpoint: \(json)")
                    runtime.process(numberOfInputs: UInt64(numberOfInputs))
                    Log.info("Processed \(numberOfInputs) input(s).")
                }
                else {
                    logAndPostErrorToTh("Failed to extract number of inputs to process from JSON: \(json).")
                    response.status = .notAcceptable // HTTP 406
                }

            }
            else {
                logAndPostErrorToTh("Message sent to /process endpoint is not valid JSON: \(request.postBodyString ?? "<nil-post-body-string>").")
                response.status = .notAcceptable // HTTP 406
            }

            self.addJsonBody(toResponse: response, json: [:], jsonDescription: "empty", endpointName: "process")
        })

        addSerialRoute(method: .post, uri: "/perturb", handler: {
            request, response in
            if
              let json = self.readRequestBody(request: request, fromEndpoint: "/perturb"),
              let perturbationPre = Perturbation(json: json),
              let intentOnFile = runtime.readIntentFromFile(perturbationPre.missionIntent.name),
              let perturbation = Perturbation(json: json, intentOnFile: intentOnFile)
            {
                Log.debug("Received valid JSON on /perturb endpoint: \(json)")
                runtime.changeIntent(perturbation.missionIntent)

                let knobsPre = intentOnFile.knobs
                let knobsPost = perturbation.missionIntent.knobs

                if
                  let corePre = knobsPre["utilizedCores"],
                  let corePost = knobsPost["utilizedCores"],
                  let corePreList = corePre.0 as? [Int],
                  let corePostList = corePost.0 as? [Int],
                  let corePreRef = corePre.1 as? Int,
                  let corePostRef = corePost.1 as? Int,
                  (corePreList != corePostList || corePreRef != corePostRef)
                {
                  runtime.scheduleInvalidated = true
                }
                if
                  let freqPre = knobsPre["utilizedCoreFrequency"],
                  let freqPost = knobsPost["utilizedCoreFrequency"],
                  let freqPreList = freqPre.0 as? [Int],
                  let freqPostList = freqPost.0 as? [Int],
                  let freqPreRef = freqPre.1 as? Int,
                  let freqPostRef = freqPost.1 as? Int,
                  (freqPreList != freqPostList || freqPreRef != freqPostRef)
                {
                  runtime.scheduleInvalidated = true
                }

                Log.info("Successfully received request on /changeIntent REST endpoint.")
            }
            else {
                logAndPostErrorToTh("Message sent to /perturb endpoint is not valid JSON: \(request.postBodyString ?? "<nil-post-body-string>").")
                response.status = .notAcceptable // HTTP 406
            }

            self.addJsonBody(toResponse: response, json: [:], jsonDescription: "empty", endpointName: "perturb")

        })

        routes.add(method: .get, uri: "/query", handler: {
            request, response in

                if let runtimeStatus = runtime.statusDictionary() {
                    self.addJsonBody(toResponse: response, json: runtimeStatus, jsonDescription: "status", endpointName: "query")
                }
                else {
                    logAndPostErrorToTh("Error while extracting status in response to request on /query REST endpoint.")
                    self.addJsonBody(toResponse: response, json: [:], jsonDescription: "empty", endpointName: "query")
                    response.status = .notAcceptable // HTTP 406
                }

            }
        )

        addSerialRoute(method: .post, uri: "/enable", handler: {
            _, response in
                let currentApplicationExecutionMode = runtime.runtimeKnobs.applicationExecutionMode.get()
                switch currentApplicationExecutionMode {
                    case .Adaptive:
                        runtime.runtimeKnobs.applicationExecutionMode.set(.NonAdaptive)
                        Log.info("Successfully received request on /enable REST endpoint. Adaptation turned off.")
                    case .NonAdaptive:
                        runtime.runtimeKnobs.applicationExecutionMode.set(.Adaptive)
                        Log.info("Successfully received request on /enable REST endpoint. Adaptation turned on.")
                    default:
                        Log.warning("Current application execution mode (\(currentApplicationExecutionMode)) is not one of {.Adaptive, .NonAdaptive}.")
                        runtime.runtimeKnobs.applicationExecutionMode.set(.Adaptive)
                        Log.info("Successfully received request on /enable REST endpoint. Adaptation turned on.")
                }
                self.addJsonBody(toResponse: response, json: [:], jsonDescription: "empty", endpointName: "enable")
        })

        routes.add(method: .post, uri: "/changeIntent", handler: {
            request, response in
                if let json = self.readRequestBody(request: request, fromEndpoint: "/changeIntent") {
                    Log.debug("Received valid JSON on /changeIntent endpoint: \(json).")
                    let missionIntent = json["missionIntent"]! as! String
                    response.status = self.changeIntent(missionIntent, accumulatedStatus: response.status)
                    Log.info("Intent change requested through /changeIntent endpoint.")
                }
                else {
                    Log.error("Did not receive valid JSON on /changeIntent endpoint: \(request)")
                }
                self.addJsonBody(toResponse: response, json: [:], jsonDescription: "empty", endpointName: "changeIntent")
            }
        )

        routes.add(method: .post, uri: "/fixConfiguration", handler: {
            request, response in
                if let json = self.readRequestBody(request: request, fromEndpoint: "/fixConfiguration") {
                    Log.debug("Received valid JSON on /fixConfiguration endpoint: \(json).")
                    runtime.controller = ConstantController()
                    var logMessage = "Proceeding with constant configuration."
                    if let knobSettingsAny = json["knobSettings"],
                       let knobSettings = knobSettingsAny as? [Any] {
                        for nameValuePairDictAny in knobSettings {
                            if let nameValuePairDict = nameValuePairDictAny as? [String : Any],
                               let nameAny = nameValuePairDict["name"],
                               let name = nameAny as? String,
                               let value = nameValuePairDict["value"] {
                                let parsedValue = parseKnobSetting(setting: value)
                                runtime.setKnob(name, to: parsedValue)
                            }
                            else {
                                fatalError("Malformed knob setting: \(nameValuePairDictAny).")
                            }
                        }
                        logMessage = "Knobs set through /fixConfiguration endpoint. " + logMessage
                    }
                    Log.info(logMessage)
                }
                else {
                    logAndPostErrorToTh("Did not receive valid JSON on /fixConfiguration endpoint: \(request)")
                }
                self.addJsonBody(toResponse: response, json: [:], jsonDescription: "empty", endpointName: "fixConfiguration")
            }
        )

        routes.add(method: .post, uri: "/terminate", handler: {
            _, response in
            runtime.shouldTerminate = true
            Log.info("Application termination requested through /terminate endpoint.")
            self.addJsonBody(toResponse: response, json: [:], jsonDescription: "empty", endpointName: "terminate")
            }
        )

        server.addRoutes(routes)

    }

}
