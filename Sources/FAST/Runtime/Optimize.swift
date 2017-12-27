/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Optimize construct
 *
 *  authors: Adam Duracz, Ferenc Bartha, Dung Nguyen
 */

//---------------------------------------

import Foundation
import Dispatch
import LoggerAPI
import HeliumLogger
import FASTController

//---------------------------------------

fileprivate let key = ["proteus","runtime"]

let compiler = Compiler()

/** Extract a value of type T from a JSON object */
func extract<T : InitializableFromString>(type: T.Type, name: String, json: [String : Any], logErrors: Bool = false) -> T? {
    if let v = json[name] {
        if let t = v as? T {
            return t
        }
        else {
            if let s = v as? String,
               let t = T(from: s) {
                return t
            }
            else if let i = v as? Int,
                    let t = T(from: "\(i)") {
                return t
            }
            else {
                if logErrors {
                    Log.error("Failed to parse value '\(v)' for key '\(name)' of type '\(T.self)' from JSON: \(json).")  
                }
                return nil
            }
        }
    }
    else {
        if logErrors {
            Log.error("No key '\(name)' in JSON: \(json).")  
        }
        return nil
    }
}

/** Start the REST server in a low-priority background thread */
fileprivate func startRestServer() -> (RestServer, InitializationParameters?) {
    
    var server: RestServer? = nil

    // Start RestServer in a background thread
    DispatchQueue.global(qos: .utility).async {
        server = FastRestServer(port: Runtime.restServerPort, address: Runtime.restServerAddress)
        server!.start()
    }

    waitUntilUp(endpoint: "alive", host: "127.0.0.1", port: Runtime.restServerPort, method: .get, description: "REST")

    if Runtime.executeWithTestHarness {

        Log.info("Posting to TH/ready.")

        if let initializationParametersJson = RestClient.sendRequest(to: "ready") {
            Log.verbose("Received response from post to TH/ready.")
            if let ips = InitializationParameters(json: initializationParametersJson) {
                return (server!, ips)
            }
            else {
                logAndPostErrorToTh("Failed to parse InitializationParameters from response from post to TH/ready: \(initializationParametersJson).")
                fatalError()
            }
        } else {
            logAndPostErrorToTh("No response from TH/ready.")
            fatalError()
        }

    }
    else {
        return (server!, nil)
    }

}

internal func initializeRandomNumberGenerators() {
    let s = initialize(type: Int.self, name: "randomSeed", from: key, or: 0)
    randomizerInit(seed: UInt64(s))
}

/* Defines an optimization scope. Replaces a loop in a pure Swift program. */
public func optimize
    ( _ id: String
    , until shouldTerminate: @escaping @autoclosure () -> Bool = false
    , across windowSize: UInt32 = 20
    , samplingPolicy: SamplingPolicy = ProgressSamplingPolicy(period: 1)
    , _ routine: @escaping (Void) -> Void ) {

    let logLevel = initialize(type: LoggerMessageType.self, name: "logLevel", from: key, or: .verbose)
    HeliumLogger.use(logLevel)

    initializeRandomNumberGenerators()

    // Start the FAST REST API, possibly obtaining initalization parameters
    // by posting to brass-th/ready
    // FIXME: This code should be moved into the initalizer for
    //        the Runtime class, once it is made non-static.
    let (restServer, initializationParameters) = startRestServer()

    /** Loop body for a given number of iterations (or infinitely, if iterations == nil) */
    func loop(iterations: UInt64? = nil, _ body: (Void) -> Void) {
        if let i = iterations {
            var localIteration: UInt64 = 0
            while localIteration < i && !shouldTerminate() && !Runtime.shouldTerminate {
                body()
                localIteration += 1
            }
        } else {
            while !shouldTerminate() && !Runtime.shouldTerminate {
                body()
            }
        }
    }

    func profile(intent: IntentSpec) {

        Log.info("Profiling optimize scope \(id).")

        Runtime.setIntent(intent)

        // Initialize measuring device, that will update measures at every input
        let measuringDevice = MeasuringDevice(ProgressSamplingPolicy(period: 1), windowSize, intent.measures)
        Runtime.measuringDevices[id] = measuringDevice

        // Number of inputs to process when profiling a configuration
        let defaultProfileSize:         UInt64 = UInt64(1000)
        // File prefix of knob- and measure tables
        let defaultProfileOutputPrefix: String = Runtime.application?.name ?? "fast"
        
        let profileSize         = initialize(type: UInt64.self, name: "profileSize",         from: key, or: defaultProfileSize)
        let profileOutputPrefix = initialize(type: String.self, name: "profileOutputPrefix", from: key, or: defaultProfileOutputPrefix) 
        
        withOpenFile(atPath: profileOutputPrefix + ".knobtable") { (knobTableOutputStream: Foundation.OutputStream) in
            withOpenFile(atPath: profileOutputPrefix + ".measuretable") { (measureTableOutputStream: Foundation.OutputStream) in

                let knobSpace = intent.knobSpace()
                let knobNames = Array(knobSpace[0].settings.keys).sorted()
                let measureNames = intent.measures
                
                func makeRow(id: Any, rest: [Any]) -> String {
                    return "\(id)\(rest.reduce( "", { l,r in "\(l),\(r)" }))\n"
                }

                // Output headers for tables
                let knobTableHeader = makeRow(id: "id", rest: knobNames)
                knobTableOutputStream.write(knobTableHeader, maxLength: knobTableHeader.characters.count)
                let measureTableHeader = makeRow(id: "id", rest: measureNames)
                measureTableOutputStream.write(measureTableHeader, maxLength: measureTableHeader.characters.count)

                for i in 0 ..< knobSpace.count {

                    let knobSettings = knobSpace[i]
                    Log.info("Start profiling of configuration: \(knobSettings.settings).")
                    knobSettings.apply()
                    if let streamingApplication = Runtime.application as? StreamApplication {
                        streamingApplication.initializeStream()
                    }
                    loop( iterations: profileSize
                        , { executeAndReportProgress(measuringDevice, routine) } )

                    // Output profile entry as line in knob table
                    let knobValues = knobNames.map{ knobSettings.settings[$0]! }
                    let knobTableLine = makeRow(id: i, rest: knobValues)
                    knobTableOutputStream.write(knobTableLine, maxLength: knobTableLine.characters.count)
                    
                    // Output profile entry as line in measure table
                    let measureValues = measureNames.map{ measuringDevice.stats[$0]!.totalAverage }
                    Log.debug("Profile for this configuration: \(zip(measureNames, measureValues).map{ "\($0): \($1)" }.joined(separator: ", ")).")
                    let measureTableLine = makeRow(id: i, rest: measureValues)
                    measureTableOutputStream.write(measureTableLine, maxLength: measureTableLine.characters.count)
                    
                }

            }
        }

    }

    
    func trace(intent: IntentSpec) {

        Log.info("Tracing optimize scope \(id).")
        if let myApp = Runtime.application as? EmulateableApplication, let myArch = Runtime.architecture as? EmulateableArchitecture {

            // step 1: Emit SQL to insert application and architecture properties based on an intent specification.
            let applicationAndArchictectureInsertion 
            = emitScriptForApplicationAndArchitectureInsertion(
                application   : myApp
                , warmupInputNum: 0
                , architecture  : myArch
                , intent        : intent)

            // step 2.1: Emit SQL to insert application input stream
            let inputStreamName = myApp.name + "_inputStream" // TODO: must pass in input stream name
            let appInputStreamInsertion 
            = emitScriptForApplicationInputStreamInsertion(applicationName: myApp.name, inputStreamName: inputStreamName)

            // step 2.2: Emit SQL to insert job log parameters (if any).
            let jobLogParamInsertion
            = emitScriptForJobLogParameterInsertion(  // TODO: must pass in energyOutlier, tapeNoise and timeOutlier
                applicationName: myApp.name,
                energyOutlier  : 64.3,
                tapeNoise      : 0.00012345,
                timeOutlier    : 18.5)

            var insertionScript = 
            "PRAGMA foreign_keys = 'off'; BEGIN;"
            + "\n" + applicationAndArchictectureInsertion  // step 1
            + "\n" + appInputStreamInsertion               // step 2.1
            + "\n" + jobLogParamInsertion                  // step 2.2
    
            // Initialize measuring device, that will update measures at every input
            let measuringDevice = MeasuringDevice(ProgressSamplingPolicy(period: 1), windowSize, intent.measures)

            // Number of inputs to process when profiling a configuration
            let defaultProfileSize: UInt64 = UInt64(1000)
            let profileSize = initialize(type: UInt64.self, name: "profileSize", from: key, or: defaultProfileSize)           
            let knobSpace = intent.knobSpace()
            
            // For application knobs that appear in the intent knob list, 
            // build the corresponding application reference configuration settings.
            // For example, for incrementer, appRefConfig = ["threshold": 10000000, "step": 1]
            var appRefConfig = [String: Any]()
            let appKnobs = myApp.getStatus()!["applicationKnobs"] as! [String : Any]
            for (appKnobName, _) in appKnobs {            
                for (knobName, rangeReferencePair) in intent.knobs {
                    if (appKnobName == knobName) {
                        appRefConfig[knobName] = rangeReferencePair.1
                    }
                }
            }
            
            // Filter out knobSpace to keep only those knobSpace[i] with settings containing appRefConfig.
            // knobAppRefSpace[i].settings = ["utilizedCores": k, "threshold": 10000000, "step": 1], for some k.
            let knobAppRefSpace = knobSpace.filter{$0.contains(appRefConfig)}
            
            // For system knobs that appear in the intent knob list,
            // build the correspnding system reference configuration settings.
            // For example, for incrementer, sysRefConfig = ["utilizedCores": 4]
            //
            var sysRefConfig = [String: Any]()
            let sysKnobs =  myArch.getStatus()!["systemConfigurationKnobs"] as! [String : Any]
            for (sysKnobName, _) in sysKnobs {            
                for (knobName, rangeReferencePair) in intent.knobs {
                    if (sysKnobName == knobName) {
                        sysRefConfig[knobName] = rangeReferencePair.1
                    }
                }
            }
            
            // Filter out knobSpace to keep only those knobSpace[i] with settings containing sysRefConfig.
            // knobSysRefSpace[i].settings = ["utilizedCores": 4, "threshold": t, "step": s] for some t and some s.
            let knobSysRefSpace = knobSpace.filter{$0.contains(sysRefConfig)}
            
            // Compute knobRefSpace = knobAppRefSpace union knobSysRefSpace
            var knobRefSpace = knobAppRefSpace
            for knobSettings in knobSysRefSpace {
                if !knobAppRefSpace.contains(knobSettings) { // no duplication allowed
                    knobRefSpace.append(knobSettings)
                }
            }                

            // loop to trace only those configurations in knobRefSpace:
            for i in 0 ..< knobRefSpace.count {

                let knobSettings = knobRefSpace[i]
                Log.info("Start tracing of configuration: \(knobSettings.settings).")
                knobSettings.apply()

                // step 3.1: Emit SQL to insert current application configuration and 
                // return the name of the current application configuration to be used in subsequent steps.
                let (currentAppConfigInsertion, currentAppConfigName)
                = emitScriptForCurrentApplicationConfigurationInsertion(application: myApp)

                // step 3.2: Emit SQL to relate the application input stream in step 2.1 
                // and the application configuration in step 3.1.
                let appInputStream_appConfigInsertion 
                = emitScriptForApplicationInputStream_ApplicationConfigurationInsertion(
                      applicationName: myApp.name
                    , inputStreamName: inputStreamName
                    , appConfigName  : currentAppConfigName)

                // step 4: Emit SQL to insert current system configuration and 
                // return the name of the current system configuration to be used in subsequent steps.
                let (currentSysConfigInsertion, currentSysConfigName) 
                = emitScriptForCurrentSystemConfigurationInsertion(architecture: myArch)

                insertionScript += 
                  "\n" + currentAppConfigInsertion             // step 3.1
                + "\n" + appInputStream_appConfigInsertion     // step 3.2
                + "\n" + currentSysConfigInsertion             // step 4

                // step 5: For each input unit in the input stream, run the CP with the given input stream, 
                // the current application configuration and current system configuration, 
                // and emit the SQL script to insert the measured delta time, delta energy.
                var inputNum = 0
                var lastTime = Runtime.getMeasure("time")!
                var lastEnergy = Runtime.getMeasure("energy")!
                var deltaTimeDeltaEnergyInsertion = ""
                loop( iterations: profileSize - 1) {
                // let numberOfProcessedInputs   = Runtime.getMeasure("iteration")   // NOTE: no such measure
                    inputNum += 1
                    executeAndReportProgress(measuringDevice, routine)
                 // let runningTime               = Runtime.getMeasure("runningTime") // NOTE: no such measure
                    let time = Runtime.getMeasure("time")!
                    let energy = Runtime.getMeasure("energy")!
                    let deltaTime = time - lastTime
                    let deltaEnergy = energy - lastEnergy
                    deltaTimeDeltaEnergyInsertion += "\n" +
                        emitScriptForDeltaTimeDeltaEnergyInsertion(
                            applicationName: myApp.name,
                            inputStreamName: inputStreamName,
                            appConfigName  : currentAppConfigName,
                            sysConfigName  : currentSysConfigName,
                            inputNumber    : inputNum,
                            deltaTime      : deltaTime,
                            deltaEnergy    : deltaEnergy           
                        )
                    lastTime = time
                    lastEnergy = energy
                }

                insertionScript += 
                "\n" + deltaTimeDeltaEnergyInsertion         // step 5
            }

            insertionScript += "\n COMMIT; PRAGMA foreign_keys = 'on';"

            // Write SQL script to file:
            let defaultProfileOutputPrefix: String = Runtime.application?.name ?? "fast"            
            let profileOutputPrefix = initialize(type: String.self, name: "profileOutputPrefix", from: key, or: defaultProfileOutputPrefix) 
            withOpenFile(atPath: profileOutputPrefix + ".trace.sql") { 
                (sqlScriptOutputStream: Foundation.OutputStream) in
                    sqlScriptOutputStream.write(insertionScript, maxLength: insertionScript.characters.count)
            }
        }

    }


    func run(model: Model, intent: IntentSpec, numberOfInputsToProcess: UInt64? = nil) {

        Log.info("Executing optimize scope \(id).")

        // Initialize the controller with the knob-to-mesure model, intent and window size
        Runtime.initializeController(model, intent, windowSize)
        
        if let controllerModel = Runtime.controller.model {
            // Compute initial schedule that meets the active intent, by using the measure values of 
            // the reference configuration as an estimate of the first measurements.            
            let currentConfiguration = controllerModel.getInitialConfiguration()!
            var currentKnobSettings = currentConfiguration.knobSettings
            let measureValuesOfReferenceConfiguration = Dictionary(Array(zip(currentConfiguration.measureNames, currentConfiguration.measureValues)))
            Log.debug("Computing schedule from model window averages: \(measureValuesOfReferenceConfiguration).")
            var schedule: Schedule = Runtime.controller.getSchedule(intent, measureValuesOfReferenceConfiguration)
            // Initialize measures
            for measure in intent.measures {
                if let measureValue = measureValuesOfReferenceConfiguration[measure] {
                    Runtime.measure(measure, measureValue)
                }
                else {
                    Log.error("Invalid model: missing values for measure '\(measure)'.")
                    fatalError()
                }
            }
            var iteration: UInt32 = 0 // iteration counter // FIXME what if the counter overflows
            var startTime = ProcessInfo.processInfo.systemUptime // used for runningTime counter
            var runningTime = 0.0 // counts only time spent inside the loop body
            Runtime.measure("iteration", Double(iteration))
            Runtime.measure("runningTime", runningTime) // running time in seconds
            Runtime.measure("currentConfiguration", Double(currentKnobSettings.kid)) // The id of the configuration given in the knobtable
            Runtime.measure("windowSize", Double(windowSize))
            // Initialize measuring device, that will update measures based on the samplingPolicy
            let measuringDevice = MeasuringDevice(samplingPolicy, windowSize, intent.measures)
            Runtime.measuringDevices[id] = measuringDevice
            // Start the input processing loop
            loop(iterations: numberOfInputsToProcess) {
                startTime = ProcessInfo.processInfo.systemUptime // reset, in case something paused execution between iterations
                if iteration > 0 && iteration % windowSize == 0 {
                    Log.debug("Computing schedule from window averages: \(measuringDevice.windowAverages()).")
                    schedule = Runtime.controller.getSchedule(intent, measuringDevice.windowAverages())
                }
                if Runtime.runtimeKnobs.applicationExecutionMode.get() == ApplicationExecutionMode.Adaptive {
                    currentKnobSettings = schedule[iteration % windowSize]                    
                    Runtime.measure("currentConfiguration", Double(currentKnobSettings.kid)) // The id of the configuration given in the knobtable
                    // FIXME This should only apply when the schedule actually needs to change knobs
                    currentKnobSettings.apply()
                }
                executeAndReportProgress(measuringDevice, routine)
                runningTime += ProcessInfo.processInfo.systemUptime - startTime
                Runtime.measure("iteration", Double(iteration))
                Runtime.measure("runningTime", runningTime) // running time in seconds
                Runtime.measure("windowSize", Double(windowSize))
                // FIXME maybe stalling in scripted mode should not be done inside of optimize but somewhere else in an independent and better way
                Runtime.reportProgress()
                
                let statusDictionary = Runtime.statusDictionary()
                Log.debug("Current status: \(convertToJsonSR4783(from: statusDictionary ?? [:])).")
                if Runtime.executeWithTestHarness {
                    // FIXME handle error from request
                    let _ = RestClient.sendRequest(to: "status", withBody: statusDictionary)
                }
                iteration += 1
            } 
        }
        else {
            Log.error("Attempt to execute using controller with undefined model.")
            fatalError()
        } 
    }

    Log.info("Application executing in \(Runtime.runtimeKnobs.applicationExecutionMode.get()) mode.")

    // Run the optimize loop, either based on initializaiton parameters 
    // from the Test Harness, or on data read from files.

    if Runtime.executeWithTestHarness {

        if let ips = initializationParameters {

            // FIXME Read a model corresponding to the initialized application,
            //       intent, and input stream.
            let model = Runtime.readModelFromFile(id)!
            
            // FIXME Use initialization parameters to initialize the Runtime

            Log.info("Posting to TH/initialized.")
            // FIXME handle error from request
            let _ = RestClient.sendRequest(to: "initialized")

            run(model: model, intent: ips.initialConditions.missionIntent, numberOfInputsToProcess: ips.numberOfInputsToProcess)

            // FIXME handle error from request
            let _ = RestClient.sendRequest(to: "done", withBody: Runtime.statusDictionary())

        }
        else {
            logAndPostErrorToTh("Invalid initalization parameters received from /ready endpoint.")
            fatalError()
        }

    }
    else {
        if let intent = Runtime.readIntentFromFile(id) {

            switch Runtime.runtimeKnobs.applicationExecutionMode.get() {
                
                case .ExhaustiveProfiling:

                    profile(intent: intent)

                case .EmulatorTracing:
 
                    trace(intent: intent)
                
                default: // .Adaptive and .NonAdaptive

                    if let model = Runtime.readModelFromFile(id) {

                        Log.info("Model loaded for optimize scope \(id).")

                        let numberOfInputsToProcess = initialize(type: UInt64.self, name: "inputsToProcess", from: key)

                        run(model: model, intent: intent, numberOfInputsToProcess: numberOfInputsToProcess)

                    } else {

                        Log.error("No model loaded for optimize scope '\(id)'. Cannot execute application in application execution mode \(Runtime.runtimeKnobs.applicationExecutionMode.get()).")
                        fatalError()

                    } 

            }
   
        } else {
            Log.warning("No intent loaded for optimize scope '\(id)'. Proceeding without adaptation.")
            loop(routine)
        }
    }

    Log.info("FAST application terminating.")
    restServer.stop()

}
