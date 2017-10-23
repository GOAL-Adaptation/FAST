/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Optimize construct
 *
 *  authors: Adam Duracz, Ferenc Bartha
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

/* A strategy for switching between KnobSettings, based on the input index. */
public class Schedule {
    let schedule: (_ progress: UInt32) -> KnobSettings
    init(_ schedule: @escaping (_ progress: UInt32) -> KnobSettings) {
        self.schedule = schedule
    }
    init(constant:  KnobSettings) {
        schedule = { (_: UInt32) in constant }
    }
    subscript(index: UInt32) -> KnobSettings {
        get {
            Log.debug("Querying schedule at index \(index)")
            return schedule(index)
        }
    }
}

/** Extract a value of type T from a JSON object */
func extract<T : InitializableFromString>(type: T.Type, name: String, json: [String : Any]) -> T? {
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
                Log.error("Failed to extract '\(name)' of type \(T.self) from JSON: '\(v)'.")  
                return nil
            }
        }
    }
    else {
        Log.error("No key \(name) in JSON.")  
        return nil
    }
}

/** Perturbation */
struct Perturbation {

    let missionIntent          : IntentSpec
    let availableCores         : UInt16
    let availableCoreFrequency : UInt64
    let missionLength          : UInt64
    let sceneObfuscation       : Double

    init?(json: [String: Any]) {
        
        if let availableCores         = extract(type: UInt16.self, name: "availableCores"        , json: json)
         , let availableCoreFrequency = extract(type: UInt64.self, name: "availableCoreFrequency", json: json)
         , let missionLength          = extract(type: UInt64.self, name: "missionLength"         , json: json)
         , let sceneObfuscation       = extract(type: Double.self, name: "sceneObfuscation"      , json: json) {

            self.availableCores         = availableCores
            self.availableCoreFrequency = availableCoreFrequency
            self.missionLength          = missionLength
            self.sceneObfuscation       = sceneObfuscation

            if let missionIntentString = json["missionIntent"] as? String {
                if let missionIntent = compiler.compileIntentSpec(source: missionIntentString) {
                    self.missionIntent = missionIntent
                }
                else {
                    Log.error("Unable to compile missionIntent from string: \(missionIntentString), which is part of the perturbation JSON: \(json).")
                    return nil   
                }
            }
            else {
                if let missionIntentJson = json["missionIntent"] as? [String : Any] {
                    let missionIntentString = RestServer.mkIntentString(from: json)
                    if let missionIntent = compiler.compileIntentSpec(source: missionIntentString) {
                        self.missionIntent = missionIntent
                    }
                    else {
                        Log.error("Unable to compile missionIntent from string: \(missionIntentString), obtained from missionIntent JSON: \(missionIntentJson), which is part of the perturbation JSON: \(json).")
                        return nil   
                    }
                }
                else {
                    Log.error("Unable to parse missionIntent from JSON: \(String(describing: json["missionIntent"])), which is part of the perturbation JSON: \(json).")
                    return nil   
                }
            }

        }
        else {
            Log.error("Unable to parse Perturbation from JSON: \(json).")
            return nil
        }

    }

}

/** Initialization Parameters */
struct InitializationParameters {

    enum ArchitectureName {
        case ArmBigLittle, XilinxZcu
    }

    enum ApplicationName {
        case radar, x264, CaPSuLe, incrementer
    }

    let architecture             : ArchitectureName
    let applicationName          : ApplicationName
    let applicationInputFileName : String
    let numberOfInputsToProcess  : UInt64  
    let adaptationEnabled        : Bool
    let statusInterval           : UInt64
    let randomSeed               : UInt64
    let initialConditions        : Perturbation

    init?(json: [String: Any]) {

        if let architecture             = extract(type: ArchitectureName.self, name: "architecture"           , json: json)
         , let applicationJson          = json["application"] as? [String : Any]
         , let applicationName          = extract(type: ApplicationName.self , name: "applicationName"        , json: applicationJson)
         , let applicationInputFileName = extract(type: String.self          , name: "InputFileName"          , json: applicationJson)
         , let numberOfInputsToProcess  = extract(type: UInt64.self          , name: "numberOfInputsToProcess", json: json)
         , let adaptationEnabled        = extract(type: Bool.self            , name: "adaptationEnabled"      , json: json)
         , let statusInterval           = extract(type: UInt64.self          , name: "statusInterval"         , json: json)
         , let randomSeed               = extract(type: UInt64.self          , name: "randomSeed"             , json: json)
         , let initialConditionsJson    = json["initialConditions"] as? [String : Any] 
         , let initialConditions        = Perturbation(json: initialConditionsJson)
        {

            self.architecture             = architecture
            self.applicationName          = applicationName
            self.applicationInputFileName = applicationInputFileName
            self.numberOfInputsToProcess  = numberOfInputsToProcess
            self.adaptationEnabled        = adaptationEnabled
            self.statusInterval           = statusInterval
            self.randomSeed               = randomSeed
            self.initialConditions        = initialConditions

        }
        else {
            Log.error("Unable to parse Perturbation from JSON: \(json).")
            return nil
        }

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
                let errorMessage = "Failed to parse InitializationParameters from response from post to TH/ready"
                Log.error(errorMessage + ": \(initializationParametersJson).")
                postErrorToTh(errorMessage + ".")
                fatalError()
            }
        } else {
            Log.error("No response from TH/ready.")
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
    , samplingPolicy: SamplingPolicy = TimingSamplingPolicy(100.millisecond)
    , _ labels: [String]
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

        // Initialize measuring device, that will update measures at every input
        let measuringDevice = MeasuringDevice(ProgressSamplingPolicy(period: 1), windowSize, labels)

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
                    loop( iterations: profileSize
                        , { executeAndReportProgress(measuringDevice, routine) } )

                    // Output profile entry as line in knob table
                    let knobValues = knobNames.map{ knobSettings.settings[$0]! }
                    let knobTableLine = makeRow(id: i, rest: knobValues)
                    knobTableOutputStream.write(knobTableLine, maxLength: knobTableLine.characters.count)
                    
                    // Output profile entry as line in measure table
                    let measureValues = measureNames.map{ measuringDevice.stats[$0]!.totalAverage }
                    let measureTableLine = makeRow(id: i, rest: measureValues)
                    measureTableOutputStream.write(measureTableLine, maxLength: measureTableLine.characters.count)
                    
                }

            }
        }

    }

    func run(model: Model, intent: IntentSpec, numberOfInputsToProcess: UInt64? = nil) {

        Log.info("Executing optimize scope \(id).")

        // Initialize the controller with the knob-to-mesure model, intent and window size
        Runtime.initializeController(model, intent, windowSize)
        
        if let controllerModel = Runtime.controller.model {
            // Initialize measuring device, that will update measures based on the samplingPolicy
            let measuringDevice = MeasuringDevice(samplingPolicy, windowSize, labels)
            var schedule: Schedule = Schedule(constant: controllerModel.getInitialConfiguration()!.knobSettings)
            // FIXME what if the counter overflows
            var iteration: UInt32 = 0 // iteration counter
            var startTime = ProcessInfo.processInfo.systemUptime // used for runningTime counter
            var runningTime = 0.0 // counts only time spent inside the loop body
            Runtime.measure("iteration", Double(iteration))
            Runtime.measure("runningTime", runningTime) // running time in seconds
            loop(iterations: numberOfInputsToProcess) {
                startTime = ProcessInfo.processInfo.systemUptime // reset, in case something paused execution between iterations
                executeAndReportProgress(measuringDevice, routine)
                iteration += 1
                if iteration % windowSize == 0 {
                    let measureWindowAverages = Dictionary(measuringDevice.stats.map{ (n,s) in (n, s.windowAverage) })
                    schedule = Runtime.controller.getSchedule(intent, measureWindowAverages)
                }
                if Runtime.runtimeKnobs.applicationExecutionMode.get() == ApplicationExecutionMode.Adaptive {
                    // FIXME This should only apply when the schedule actually needs to change knobs
                    schedule[iteration % windowSize].apply()
                }
                Runtime.measure("iteration", Double(iteration))
                runningTime += ProcessInfo.processInfo.systemUptime - startTime
                Runtime.measure("runningTime", runningTime) // running time in seconds
                // FIXME maybe stalling in scripted mode should not be done inside of optimize but somewhere else in an independent and better way
                Runtime.reportProgress()
                
                if Runtime.executeWithTestHarness {
                    // FIXME handle error from request
                    let _ = RestClient.sendRequest(to: "status", withBody: Runtime.statusDictionary())
                }
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
            let model = Runtime.loadModel(id)!
            
            // FIXME Use initialization parameters to initialize the Runtime

            Log.info("Posting to TH/initialized.")
            // FIXME handle error from request
            let _ = RestClient.sendRequest(to: "initialized")

            run(model: model, intent: ips.initialConditions.missionIntent, numberOfInputsToProcess: ips.numberOfInputsToProcess)

            // FIXME handle error from request
            let _ = RestClient.sendRequest(to: "done", withBody: Runtime.statusDictionary())

        }
        else {
            let errorMessage =  "Invalid initalization parameters received from /ready endpoint."
            Log.error(errorMessage)
            postErrorToTh(errorMessage)
            fatalError()
        }

    }
    else {
        if let intent = Runtime.loadIntent(id) {

            switch Runtime.runtimeKnobs.applicationExecutionMode.get() {
                
                case .ExhaustiveProfiling:

                    profile(intent: intent)
                
                default: // .Adaptive and .NonAdaptive

                    if let model = Runtime.loadModel(id) {

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
