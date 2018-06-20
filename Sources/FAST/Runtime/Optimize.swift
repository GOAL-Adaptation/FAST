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
import CSwiftV
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
fileprivate func startRestServer(using runtime: Runtime) -> (RestServer, InitializationParameters?) {

    var server: RestServer? = nil

    // Start RestServer in a background thread
    DispatchQueue.global(qos: .utility).async {
        server = FastRestServer(port: runtime.restServerPort, address: runtime.restServerAddress, runtime: runtime)
        server!.start()
    }

    waitUntilUp(endpoint: "alive", host: "127.0.0.1", port: runtime.restServerPort, method: .get, description: "REST")

    if runtime.executeWithTestHarness {

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
func optimize
    ( _ id: String
    , _ runtime: Runtime
    , until shouldTerminate: @escaping @autoclosure () -> Bool = false
    , across windowSize: UInt32 = 20
    , samplingPolicy: SamplingPolicy = ProgressSamplingPolicy(period: 1)
    , _ routine: @escaping () -> Void ) {

    initializeRandomNumberGenerators()

    // Start the FAST REST API, possibly obtaining initalization parameters
    // by posting to brass-th/ready
    // FIXME: This code should be moved into the initalizer for
    //        the Runtime class, once it is made non-static.
    let (restServer, initializationParameters) = startRestServer(using: runtime)

    // initialize local variables used to compute measures
    var iteration: UInt32 = 0 // iteration counter // FIXME what if the counter overflows
    var startTime = ProcessInfo.processInfo.systemUptime // used for runningTime counter
    var runningTime = 0.0 // counts only time spent inside the loop body
    var energy = 0.0 // counts only energy spent inside the loop body

    /** Re-set the internal variables used to compute measures, and register them in the runtime */
    func resetMeasures() {
        Log.debug("optimize.resetMeasuresBegin")
        iteration = 0 // iteration counter // FIXME what if the counter overflows
        startTime = ProcessInfo.processInfo.systemUptime // used for runningTime counter
        runningTime = 0.0 // counts only time spent inside the loop body
        energy = 0.0 // counts only energy spent inside the loop body
        runtime.resetRuntimeMeasures(windowSize: windowSize)
        Log.debug("optimize.resetMeasuresEnd")
    }

    /**
     * Derived measures are computed from the original measures using this function. This is used
     * to ensure correct calculation of profiling entries where, rathen than from the standard total 
     * average of the individual derived measure values, the profiling entries must be computed in
     * terms of this function. For example, if latencies are "1,2,3", then the average latency
     * is (1+2+3)/3, and the average performance is 1/((1+2+3)/3), rather than (1/1+1/2+1/3)/3.
     */
    func computeDerivedMeasure(_ measureName: String, _ measureGetter: (String) -> Double) -> Double {
        switch measureName {
            case "performance": 
                return 1.0 / measureGetter("latency")
            case "powerConsumption": 
                return measureGetter("energyDelta") / measureGetter("latency")
            case "energyRemaining":
                return measureGetter("energyLimit") - measureGetter("energy")
            default:
                return measureGetter(measureName)
        }
    }

    /** Obtains a measure's value from the runtime */
    func runtimeMeasureValueGetter(_ measureName: String) -> Double {
        if let measureValue = runtime.getMeasure(measureName) {
            return measureValue
        }
        else {
            Log.error("No value for measure '\(measureName)' available in runtime. Valid measures are: \(runtime.getMeasures().keys).")
            fatalError()
        }
    }

    /** 
     * Loop body for a given number of iterations (or infinitely, if iterations == nil) 
     * Note: The overhead of preBody and postBody are excluded measures.
     */
    func loop( iterations: UInt64? = nil
             , preBody:  @escaping () -> Void = {}
             , postBody: @escaping () -> Void = {}
             , _ body:   @escaping () -> Void
             ) {

        /** Execute preBody, execute body, update measures provided by runtime, and update postBody. */
        func executeBodyAndComputeMeasures() {
            Log.debug("optimize.loop.updateMeasuresBegin")
            // When in scripted mode, block until a post to the /process endpoint
            runtime.waitForRestCallToIncrementScriptedCounter()
            // Increment the iteration measure
            iteration += 1
            // Note that one less iteration is left to be processed when in scripted mode
            runtime.decrementScriptedCounter()
            // Run preparatory code for this iteration, e.g. to reconfigure the system using a controller
            preBody()
            // Record values of time and energy before executing the loop body
            let systemEnergyBefore = runtime.getMeasure("systemEnergy")!
            let timeBefore = runtime.getMeasure("time")! // begin measuring latency
            // Run the loop body
            body()
            // Run wrap-up code for this iteration, e.g. to report progress to a measuring device
            postBody()
            let timeAfter = runtime.getMeasure("time")! // stop measuring latency
            // Measure the iteration counter
            runtime.measure("iteration", Double(iteration))
            runtime.measure("windowSize", Double(windowSize))
            // Compute the latency, and if that is greater than 0, record derived measures
            let latency: Double = timeAfter - timeBefore
            if latency > 0.0 {
                
                let systemEnergyAfter = runtime.getMeasure("systemEnergy")!
                let energyDelta: Double = systemEnergyAfter - systemEnergyBefore
                
                runningTime += latency
                energy += energyDelta

                runtime.measure("latency", latency) // latency in seconds
                runtime.measure("energyDelta", energyDelta) // energy per iteration
                runtime.measure("energy", energy) // energy since application started or was last reset
                runtime.measure("runningTime", runningTime) // running time in seconds
                runtime.measure("performance", 
                    computeDerivedMeasure("performance", runtimeMeasureValueGetter)) // seconds per iteration
                runtime.measure("powerConsumption", 
                    computeDerivedMeasure("powerConsumption", runtimeMeasureValueGetter)) // rate of energy
                // If running in Adaptive mode, the energyLimit is defined
                if let theEnergyLimit = runtime.energyLimit {
                    runtime.measure("energyLimit", Double(theEnergyLimit))
                    runtime.measure("energyRemaining", 
                        computeDerivedMeasure("energyRemaining", runtimeMeasureValueGetter))
                } 
            }
            else {
                Log.debug("Zero time passed between two measurements of time. The performance and powerConsumption measures cannot be computed.")
            }
            Log.debug("optimize.loop.updateMeasuresEnd")
        }

        // Wait for the system measures to be read
        while runtime.getMeasure("time") == nil || runtime.getMeasure("systemEnergy") == nil {
            usleep(10000) // sleep 10ms
        }

        if let initialMissionLength = iterations {
            Log.verbose("Starting execution bounded by missionLength parameter to \(initialMissionLength) iterations.")
            while !shouldTerminate() && !runtime.shouldTerminate && UInt64(runtime.getMeasure("iteration")!) < runtime.scenarioKnobs.missionLength.get() {
                executeBodyAndComputeMeasures()
            }
            Log.verbose("Ending execution bounded by missionLength parameter to \(runtime.scenarioKnobs.missionLength.get()) iterations.")
        } else {
            Log.verbose("Starting execution unbounded by missionLength parameter.")
            while !shouldTerminate() && !runtime.shouldTerminate {
                executeBodyAndComputeMeasures()
            }
            Log.verbose("Ending execution unbounded by missionLength parameter.")
        }
    }

    func profile(intent: IntentSpec, exhaustive: Bool = true) {

        Log.info("Profiling optimize scope \(id).")

        runtime.setIntent(intent)

        // Number of inputs to process when profiling a configuration
        let defaultProfileSize:         UInt64 = UInt64(1000)
        // File prefix of knob- and measure tables
        let defaultProfileOutputPrefix: String = runtime.application?.name ?? "fast"

        let profileSize         = initialize(type: UInt64.self, name: "missionLength",       from: key, or: defaultProfileSize)
        let profileOutputPrefix = initialize(type: String.self, name: "profileOutputPrefix", from: key, or: defaultProfileOutputPrefix)

        let knobTablePath = profileOutputPrefix + ".knobtable"

        // Returns the highest id present in the knob table, 
        // used to continue interrupted profiling runs.
        var lastComputedProfileEntry: Int = -1
        do {
            let knobFileString = try String(contentsOf: URL(fileURLWithPath: knobTablePath), encoding: .utf8)
            let knobCSV = CSwiftV(with: knobFileString)
            if let indexOfIdColumn = knobCSV.headers.index(where: { $0 == "id" }) {
                let ids = knobCSV.rows.map{ Int($0[indexOfIdColumn])! }
                lastComputedProfileEntry = ids.max() ?? -1
            }
            else {
                Log.info("Invalid knob table found at '\(knobTablePath)'.")
                fatalError()
            }
        }
        catch {
            Log.info("No knob table found at '\(knobTablePath)', profiling from scratch.")
        }

        withOpenFile(atPath: knobTablePath, append: true) { (knobTableOutputStream: Foundation.OutputStream) in
            withOpenFile(atPath: profileOutputPrefix + ".measuretable", append: true) { (measureTableOutputStream: Foundation.OutputStream) in
                withOpenFile(atPath: profileOutputPrefix + ".variancetable", append: true) { (varianceTableOutputStream: Foundation.OutputStream) in

                    let knobSpace = intent.knobSpace(exhaustive: exhaustive)
                    let knobNames = Array(knobSpace[0].settings.keys).sorted()
                    let measureNames = Array(Set(intent.measures + runtime.runtimeAndSystemMeasures)).sorted()

                    func makeRow(id: Any, rest: [Any]) -> String {
                        return "\(id)\(rest.reduce( "", { l,r in "\(l),\(r)" }))\n"
                    }

                    // Output headers for tables
                    if lastComputedProfileEntry < 0 {
                        let knobTableHeader = makeRow(id: "id", rest: knobNames)
                        knobTableOutputStream.write(knobTableHeader, maxLength: knobTableHeader.count)
                        let measureTableHeader = makeRow(id: "id", rest: measureNames)
                        measureTableOutputStream.write(measureTableHeader, maxLength: measureTableHeader.count)
                        let varianceTableHeader = makeRow(id: "id", rest: measureNames)
                        varianceTableOutputStream.write(varianceTableHeader, maxLength: varianceTableHeader.count)
                    }                    

                    for i in 0 ..< knobSpace.count {

                        if i <= lastComputedProfileEntry {
                            Log.verbose("Skip profiling of configuration with id \(i), which is already present in the knob table: \(knobTablePath).")
                            continue
                        }

                        let knobSettings = knobSpace[i]
                        Log.info("Start profiling of configuration: \(knobSettings.settings).")
                        knobSettings.apply(runtime: runtime)

                        // Ensure that successive runs do not affect one-another's measures
                        resetMeasures()
                        // Initialize measuring device, that will update measures at every input
                        let measuringDevice = MeasuringDevice(ProgressSamplingPolicy(period: 1), windowSize, intent.measures, runtime)
                        runtime.measuringDevices[id] = measuringDevice
                        // If the application processes an input stream, re-initialize it
                        if let streamingApplication = runtime.application as? StreamApplication {
                            streamingApplication.initializeStream()
                        }
                        loop( iterations: profileSize
                            , postBody: {
                                measuringDevice.reportProgress()
                                let statusDictionary = runtime.statusDictionary()
                                Log.debug("\nCurrent status: \(convertToJsonSR4783(from: statusDictionary ?? [:])).\n")
                            }) 
                        {
                            startTime = ProcessInfo.processInfo.systemUptime // reset, in case something paused execution between iterations
                            routine() // execute the routine (body of the optimize constuct)
                        }

                        // Output profile entry as line in knob table
                        let knobValues = knobNames.map{ knobSettings.settings[$0]! }
                        let knobTableLine = makeRow(id: i, rest: knobValues)
                        knobTableOutputStream.write(knobTableLine, maxLength: knobTableLine.characters.count)

                        /** Obtains a measure's total average from the measuringDevice */
                        func runtimeMeasureTotalAverageGetter(_ measureName: String) -> Double {
                            if let measureStats = measuringDevice.stats[measureName] {
                                return measureStats.totalAverage
                            }
                            else {
                                Log.error("No statistics for measure '\(measureName)' available in measuring device. Valid measures are: \(measuringDevice.stats.keys).")
                                fatalError()
                            }
                        }

                        // Output profile entry as line in measure table
                        let measureValues = measureNames.map{ computeDerivedMeasure($0, runtimeMeasureTotalAverageGetter) }
                        let measureTableLine = makeRow(id: i, rest: measureValues)
                        measureTableOutputStream.write(measureTableLine, maxLength: measureTableLine.characters.count)

                        // Output profile entry as line in variance table
                        let varianceValues = measureNames.map{ measuringDevice.stats[$0]!.totalVariance }
                        let varianceTableLine = makeRow(id: i, rest: varianceValues)
                        varianceTableOutputStream.write(varianceTableLine, maxLength: varianceTableLine.characters.count)

                    }
                }
            }
        }
    }


    func trace(intent: IntentSpec) {

        Log.info("Tracing optimize scope \(id).")
        runtime.setIntent(intent)

        // FIXME: Externalize as environment variables
        let warmupInputNum = 0
        let energyOutlier  = 64.3
        let tapeNoise      = 0.001953125
        let timeOutlier = 16.1
        
        guard 
            let myApp  = runtime.application as? EmulateableApplication, 
            let myArch = runtime.architecture as? EmulateableArchitecture 
        else {
            fatalError("Cannot trace since either the application or the architecture are not emulatable.")
        }

        // Initialize dictionaries for JSON database
        let applicationId                    = 0 // JSON database only supports a single application
        let applicationInputID               = runtime.applicationInputId // JSON database only supports a single input stream
        var getCurrentAppConfigurationIdDict = [ KnobSettings                         : Int                             ]()
        var getCurrentSysConfigurationIdDict = [ KnobSettings                         : Int                             ]()
        var tracedConfigurations             = [ DictDatabase.ProfileEntryId                                            ]()
        var readDeltaDict                    = [ DictDatabase.ProfileEntryIterationId : DictDatabase.TimeAndEnergyDelta ]()

        let inputStreamName = myApp.name + "_inputStream" // TODO: must pass in input stream name

        // Number of inputs to process when profiling a configuration
        let traceSize = initialize(type: UInt64.self, name: "missionLength", from: key, or: UInt64(1000))
        let knobSpace = intent.knobSpace()
        
        Log.info("Tracing configuration space of size \(knobSpace.count) over \(traceSize) iterations: \(knobSpace).")

        for i in 0 ..< knobSpace.count {

            resetMeasures()

            // Initialize measuring device, that will update measures at every input
            let measuringDevice = MeasuringDevice(ProgressSamplingPolicy(period: 1), windowSize, intent.measures, runtime)
            runtime.measuringDevices[id] = measuringDevice

            let knobSettings = knobSpace[i]
            Log.info("Start tracing of configuration \(i): \(knobSettings.settings).")
            knobSettings.apply(runtime: runtime)
            if let streamingApplication = runtime.application as? StreamApplication {
                streamingApplication.initializeStream()
            }

            // Assign an ID to the current configuration (of knobType) and insert that into idDict
            func assignIdToConfiguration(knobType: String, module: TextApiModule, to idDict: inout [KnobSettings : Int]) -> Int {
                let knobs = module.getStatus()![knobType] as! [String : Any]
                let knobSettings = KnobSettings(kid: -1, DictDatabase.unwrapKnobStatus(knobStatus: knobs))
                let id = knobSpace.index(where: { $0.contains(knobSettings.settings) })!
                if idDict[knobSettings] == nil {
                    idDict[knobSettings] = id
                }
                return idDict[knobSettings]!
            }
            // The id of an application configuration KnobSettings as its position in the knobSysRefSpace
            let applicationConfigurationId = assignIdToConfiguration(knobType: "applicationKnobs"        , module: myApp , to: &getCurrentAppConfigurationIdDict)
            // The id of a system configuration KnobSettings as its position in the knobAppRefSpace
            let systemConfigurationId      = assignIdToConfiguration(knobType: "systemConfigurationKnobs", module: myArch, to: &getCurrentSysConfigurationIdDict)
            // Register the profileEntryId of the current knobSettings in tracedConfigurations
            let profileEntryId = 
                DictDatabase.ProfileEntryId( 
                      applicationConfigurationId : applicationConfigurationId
                    , applicationInputId         : applicationInputID
                    , systemConfigurationId      : systemConfigurationId
                    )
            tracedConfigurations.append(profileEntryId)

            // For each input unit in the input stream, run the CP with the given input stream,
            // the current application configuration and current system configuration,
            // and insert the measured delta time, delta energy into the database.
            var inputNum = 0
            var lastTime = runtime.getMeasure("time")!
            var lastEnergy = runtime.getMeasure("energy")!
            var deltaTimeDeltaEnergyInsertion = ""
            loop( iterations: traceSize
                , postBody: { measuringDevice.reportProgress() } ) 
            {
                routine()
                let time = runtime.getMeasure("time")!
                let energy = runtime.getMeasure("energy")!
                let deltaTime = time - lastTime
                let deltaEnergy = energy - lastEnergy

                let profileEntryIterationId = 
                    DictDatabase.ProfileEntryIterationId(profileEntryId : profileEntryId, iteration: inputNum) 

                readDeltaDict[profileEntryIterationId] = DictDatabase.TimeAndEnergyDelta(timeDelta: deltaTime, energyDelta: deltaEnergy)

                lastTime = time
                lastEnergy = energy
                inputNum += 1
            }

        }

        let profileOutputPrefix = initialize(type: String.self, name: "profileOutputPrefix", from: key, or: runtime.application?.name ?? "fast")

        // Write JSON database to file:
        let dicts = DictDatabase.Dicts(
              applicationName                     : myApp.name
            , architectureName                    : myArch.name
            , inputStreamName                     : inputStreamName
            , getCurrentAppConfigurationIdDict    : getCurrentAppConfigurationIdDict
            , getCurrentSysConfigurationIdDict    : getCurrentSysConfigurationIdDict
            , warmupInputs                        : warmupInputNum 
            , numberOfInputsTraced                : Int(traceSize)
            , tracedConfigurations                : tracedConfigurations
            , tapeNoise                           : tapeNoise
            , applicationId                       : applicationId
            , timeOutlier                         : timeOutlier
            , energyOutlier                       : energyOutlier
            , applicatioInputStreamId             : applicationInputID
            , readDeltaDict                       : readDeltaDict
        )
        guard let encodedDicts = try? JSONEncoder().encode(dicts) else {
            fatalError("Can not encode tracing database as JSON: \(dicts).")
        }
        withOpenFile(atPath: profileOutputPrefix + ".trace.json") {
            (jsonOutputStream: Foundation.OutputStream) in
                jsonOutputStream.write(String(decoding: encodedDicts, as: UTF8.self), maxLength: encodedDicts.count)
        }

    }


    func run(model: Model?, intent: IntentSpec, missionLength: UInt64, enforceEnergyLimit: Bool) {

        Log.info("Running optimize scope \(id).")

        /** 
         * Compute the energyLimit as the amount of energy that must be available 
         * to the system when it starts, to complete the missionLength assuming that 
         * it is always executing in the most energy-inefficient configuration, that 
         * is, the one with the highest energyDelta.
         */
        func computeEnergyLimit() -> UInt64? {

            switch runtime.runtimeKnobs.applicationExecutionMode.get() {
                
                case .Adaptive:

                    if let controllerModel = model {
                        let modelSortedByEnergyDeltaMeasure = controllerModel.sorted(by: "energyDelta")
                        if 
                            let energyDeltaMeasureIdx            = modelSortedByEnergyDeltaMeasure.measureNames.index(of: "energyDelta"),
                            let modelEnergyDeltaMaxConfiguration = modelSortedByEnergyDeltaMeasure.configurations.last,
                            let modelEnergyDeltaMinConfiguration = modelSortedByEnergyDeltaMeasure.configurations.first
                        {
                            let modelEnergyDeltaMax = UInt64(modelEnergyDeltaMaxConfiguration.measureValues[energyDeltaMeasureIdx])
                            let modelEnergyDeltaMin = UInt64(modelEnergyDeltaMinConfiguration.measureValues[energyDeltaMeasureIdx])

                            let energyLimit = modelEnergyDeltaMax * missionLength
                            let maxMissionLength = energyLimit / modelEnergyDeltaMin

                            Log.verbose("An energyLimit of \(energyLimit) was computed based on a missionLength of \(missionLength) and least energy-efficient model configuration with energyDelta \(modelEnergyDeltaMax). Maximum missionLength with this energyLimit is \(maxMissionLength)")

                            return energyLimit
                        }
                        else {
                            Log.error("Model is missing the energyDelta measure. Can not compute energyLimit.")
                            fatalError("")
                        }
                    }
                    else {
                        Log.error("No model loaded. Can not compute energyLimit.")
                        fatalError("")
                    }

                case .NonAdaptive:

                    Log.verbose("Executing in NonAdaptive mode, no energyLimit computed.")
                    return nil

                default:
                    
                    fatalError("Attempt to execute in unsupported execution mode: \(runtime.runtimeKnobs.applicationExecutionMode.get()).")
            }

        }

        func setUpControllerAndComputeInitialScheduleAndConfiguration() -> (Schedule,KnobSettings) {
            switch runtime.runtimeKnobs.applicationExecutionMode.get() {
                
                case .Adaptive:

                    if let controllerModel = model {

                        // Initialize the controller with the knob-to-mesure model, intent and window size
                        runtime.initializeController(controllerModel, intent, windowSize, missionLength, enforceEnergyLimit)

                        // Compute initial schedule that meets the active intent, by using the measure values of
                        // the reference configuration as an estimate of the first measurements.
                        let currentConfiguration = controllerModel.getInitialConfiguration()!
                        let currentKnobSettings = currentConfiguration.knobSettings
                        let measureValuesOfReferenceConfiguration = Dictionary(Array(zip(currentConfiguration.measureNames, currentConfiguration.measureValues)))
                        // Initialize measures
                        for measure in intent.measures {
                            if let measureValue = measureValuesOfReferenceConfiguration[measure] {
                                runtime.measure(measure, measureValue)
                            }
                            else {
                                Log.error("Invalid model: missing values for measure '\(measure)'.")
                                fatalError()
                            }
                        }

                        let initialSchedule = runtime.controller.getSchedule(intent, measureValuesOfReferenceConfiguration)
                        Log.verbose("Computed initial schedule from model referece configuration window averages: \(measureValuesOfReferenceConfiguration).")

                        return (initialSchedule, currentKnobSettings) 
                    }
                    else {
                        Log.error("Attempt to execute in adaptive mode using controller with undefined model.")
                        fatalError()
                    }

                case .NonAdaptive:

                    // Initialize the constant controller with the reference configuration from the intent
                    let currentKnobSettings = intent.referenceKnobSettings()
                    runtime.controller = ConstantController(knobSettings: currentKnobSettings) 
                    runtime.setIntent(intent)        

                    // Initialize measures
                    for measure in intent.measures {
                        runtime.measure(measure, 0.0)
                    }

                    Log.verbose("Using constant schedule computed by the controller based on using 0.0 as the value for all measures.")
                    let schedule = runtime.controller.getSchedule(intent, runtime.getMeasures())
                   
                    return (schedule, currentKnobSettings)
                
                default:
                    
                    fatalError("Attempt to execute in unsupported execution mode: \(runtime.runtimeKnobs.applicationExecutionMode.get()).")

            }
        }
        
        runtime.energyLimit = computeEnergyLimit() // Initialize the runtime's energyLimit based on the model

        var (schedule, currentKnobSettings) = setUpControllerAndComputeInitialScheduleAndConfiguration()
        runtime.schedule = schedule // Initialize the runtime's schedule
        var lastKnobSettings = currentKnobSettings

        runtime.measure("currentConfiguration", Double(currentKnobSettings.kid)) // The id of the configuration given in the knobtable

        resetMeasures()

        // Initialize measuring device, that will update measures based on the samplingPolicy
        let measuringDevice = MeasuringDevice(samplingPolicy, windowSize, intent.measures, runtime)
        runtime.measuringDevices[id] = measuringDevice

        // Start the input processing loop
        loop( iterations: missionLength
            , preBody: {
                // Request a new schedule if this is the first iteration of a window, 
                // or if the schedule has been invalidated (e.g. by the /perturb endpoint)
                if (iteration > 0 && iteration % windowSize == 0) || runtime.schedule == nil {
                    Log.debug("Computing schedule from window averages: \(measuringDevice.windowAverages()).")
                    runtime.schedule = runtime.controller.getSchedule(runtime.intents[id]!, measuringDevice.windowAverages())
                }
                if runtime.runtimeKnobs.applicationExecutionMode.get() == ApplicationExecutionMode.Adaptive {
                    currentKnobSettings = runtime.schedule![iteration % windowSize]
                    runtime.measure("currentConfiguration", Double(currentKnobSettings.kid)) // The id of the configuration given in the knobtable
                    if currentKnobSettings != lastKnobSettings {
                        Log.verbose("Scheduled configuration has changed since the last iteration, will apply knob settings.")
                        currentKnobSettings.apply(runtime: runtime)
                        lastKnobSettings = currentKnobSettings
                    }
                    else {
                        Log.debug("Scheduled configuration has not changed since the last iteration, will skip applying knob settings.")
                    }
                }
            }
            , postBody: {
                measuringDevice.reportProgress()
                let statusDictionary = runtime.statusDictionary()
                Log.debug("\nCurrent status: \(convertToJsonSR4783(from: statusDictionary ?? [:])).\n")
                if runtime.executeWithTestHarness {
                    // FIXME handle error from request
                    let _ = RestClient.sendRequest(to: "status", withBody: statusDictionary)
                }
            }) 
        {
            startTime = ProcessInfo.processInfo.systemUptime // reset, in case something paused execution between iterations
            routine() // execute the routine (body of the optimize constuct)
        }
        
    }

    Log.info("\nApplication executing in \(runtime.runtimeKnobs.applicationExecutionMode.get()) mode.\n")

    // Run the optimize loop, either based on initializaiton parameters
    // from the Test Harness, or on data read from files.

    if runtime.executeWithTestHarness {

        if let ips = initializationParameters {

            // FIXME Read a model corresponding to the initialized application,
            //       intent, and input stream.
            let model = runtime.readModelFromFile(id, intent: ips.initialConditions.missionIntent)!

            Log.debug("Using initialization parameters from test harness: \(ips.asDict()).")

            Log.info("Posting to TH/initialized.")
            // FIXME handle error from request
            let _ = RestClient.sendRequest(to: "initialized")

            runtime.setScenarioKnobs(accordingTo: ips.initialConditions)

            run(model: model, intent: ips.initialConditions.missionIntent, missionLength: ips.initialConditions.missionLength, enforceEnergyLimit: ips.initialConditions.enforceEnergyLimit)

        }
        else {
            logAndPostErrorToTh("Invalid initalization parameters received from /ready endpoint.")
            fatalError()
        }

    }
    else {
        if let intent = runtime.readIntentFromFile(id) {

            switch runtime.runtimeKnobs.applicationExecutionMode.get() {

                case .ExhaustiveProfiling:

                    profile(intent: intent)

                case .EndPointsProfiling:

                    profile(intent: intent, exhaustive: false)

                case .EmulatorTracing:

                    trace(intent: intent)

                case .Adaptive:

                    if let model = runtime.readModelFromFile(id, intent: intent) {
                        Log.info("Model loaded for optimize scope \(id).")

                        if 
                            let missionLength      = initialize(type: UInt64.self, name: "missionLength"     , from: key),
                            let enforceEnergyLimit = initialize(type: Bool.self  , name: "enforceEnergyLimit", from: key)
                        {
                            run(model: model, intent: intent, missionLength: missionLength, enforceEnergyLimit: enforceEnergyLimit)
                        }
                        else {
                            Log.error("The  missionLength and enforceEnergyLimit parameters (mandatory for Adaptive execution) could not be initialized.")
                            fatalError()
                        }

                    } else {
                        Log.error("No model loaded for optimize scope '\(id)'. Cannot execute application in application execution mode \(runtime.runtimeKnobs.applicationExecutionMode.get()).")
                        fatalError()
                    }

                case .NonAdaptive:

                    if 
                        let missionLength = initialize(type: UInt64.self, name: "missionLength", from: key)
                    {
                        // No model for ConstantController, energyLimit not defined or enforced
                        run(model: nil, intent: intent, missionLength: missionLength, enforceEnergyLimit: false)
                    }
                    else {
                        Log.error("The missionLength parameter (mandatory for NonAdaptive execution) could not be initialized.")
                        fatalError()
                    }
            
                default:

                    fatalError("Attempt to execute in unsupported execution mode: \(runtime.runtimeKnobs.applicationExecutionMode.get()).")
            }

        } else {
            Log.warning("No intent loaded for optimize scope '\(id)'. Proceeding without adaptation.")
            loop(routine)
        }
    }

    Log.info("FAST application terminating.")

    // Stop the rest server and report the reason
    if 
        let ips = initializationParameters,
        let iteration = runtime.getMeasure("iteration")
    {
        if iteration + 1 < Double(ips.initialConditions.missionLength) { // + 1 because "iteration" starts from 0
            restServer.stop(error: "Execution terminated before processing the missionLength (\(ips.initialConditions.missionLength)) specified at initialization or the latest perturbation.")
        }
        else {
            if runtime.scriptedCounter > 0 {
                restServer.stop(error: "Execution terminated before processing the missionLength (\(ips.initialConditions.missionLength)) specified at initialization or the latest perturbation, but did not process \(runtime.scriptedCounter) iteration(s) requested by the latest post to the /process endpoint.")
            }
            else {
                restServer.stop()
            }
        }
    }
    else {
        restServer.stop()
    }

}
