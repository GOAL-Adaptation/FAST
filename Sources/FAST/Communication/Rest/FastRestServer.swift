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
              let perturbation = Perturbation(json: json)
            {
                Log.debug("Received valid JSON on /perturb endpoint: \(json)")

                guard 
                    let intentBeforePerturbation = runtime.intents[perturbation.missionIntent.name],
                    let (_, unTrimmedModelBeforePerturbation) = runtime.models[perturbation.missionIntent.name] 
                else {
                    FAST.fatalError("Perturbation intent name '\(perturbation.missionIntent.name)' does not correspond to any registered application name. Known applications are: '\(runtime.intents.keys)'.")
                }

                // The scenario knobs (availableCores, availableCoreFrequency) 
                // act as filters on the corresponding knobs in the intent.
                runtime.setScenarioKnobs(accordingTo: perturbation)

                if perturbation.scenarioChanged || !intentBeforePerturbation.isEqual(to: perturbation.missionIntent) {
                    Log.debug("Perturbation changed intent in a way that produced valid knob ranges. Reinitializing controller and invalidating current schedule.")
                    // Reinitialize the controller with the new intent
                    runtime.registerIntentAndModel(for: perturbation.missionIntent, unTrimmedModelBeforePerturbation)
                }
                else {
                    Log.verbose("Perturbation did not change the intent, or did so in a way that did not produce valid knob ranges. Did not invalidate current schedule.")
                }

                Log.info("Successfully received request on /perturb REST endpoint.")
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

        routes.add(method: .post, uri: "/fixConfiguration", handler: {
            request, response in
                if let json = self.readRequestBody(request: request, fromEndpoint: "/fixConfiguration") {
                    
                    Log.debug("Received valid JSON on /fixConfiguration endpoint: \(json).")

                    runtime.runtimeKnobs.applicationExecutionMode.set(ApplicationExecutionMode.NonAdaptive)
                    runtime.controller = ConstantController()
                    
                    var logMessage = "Proceeding with constant configuration."
                    
                    if let knobSettingsAny = json["knobSettings"],
                       let knobSettings = knobSettingsAny as? [Any] {

                        var parsedKnobSettings: [String : Any] = [:]
                        
                        for nameValuePairDictAny in knobSettings {
                            if let nameValuePairDict = nameValuePairDictAny as? [String : Any],
                               let nameAny = nameValuePairDict["name"],
                               let name = nameAny as? String,
                               let value = nameValuePairDict["value"] {

                                parsedKnobSettings[name] = parseKnobSetting(setting: value)

                            }
                            else {
                                FAST.fatalError("Malformed knob setting: \(nameValuePairDictAny).")
                            }
                            let fixedConfiguration = KnobSettings(kid: -1, parsedKnobSettings)
                            // Overwrite any existing schedule to prevent it from overwriting the fixed 
                            // configuration before the end of the current window
                            runtime.schedule = Schedule(constant: fixedConfiguration)
                            // Apply the fixed configuration
                            fixedConfiguration.apply(runtime: runtime)
                            // Update the currentKnobSettings
                            runtime.currentKnobSettings = fixedConfiguration
                        }
                        logMessage = "Knobs set through /fixConfiguration endpoint. " + logMessage
                    }
                    else {
                        Log.warning("No knob settings received in call to /fixConfiguation with message body: \(json).")
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
