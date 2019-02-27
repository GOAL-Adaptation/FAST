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
                FAST.fatalError("Failed to parse InitializationParameters from response from post to TH/ready: \(initializationParametersJson).")
            }
        } else {
            FAST.fatalError("No response from TH/ready.")
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
            FAST.fatalError("No value for measure '\(measureName)' available in runtime. Valid measures are: \(runtime.getMeasures().keys).")
        }
    }

    /**
     * Gather timing statistics about various segments of code.
     * The "timers" dictionary is populated with timers, with labels such
     * as "preBody" and "body", to provide low-level performance debugging 
     * information.
     */
    var timers = [String:Double]()
    func startMeasuring(_ label: String) {
        timers["_" + label] = NSDate().timeIntervalSince1970
    }
    func stopMeasuring(_ label: String) {
        guard let timeOfLastStartMeasuring = timers["_" + label] else {
            FAST.fatalError("Runtime error: timer '\(label)' stopped before it was started!")
        }
        let timerSoFar = timers[label] ?? 0.0
        timers[label] = timerSoFar + (NSDate().timeIntervalSince1970 - timeOfLastStartMeasuring)
    }
    func logTimingReport() {
        let longestLabelLength = timers.keys.map{ k in k.count }.max()
        let wholeExecutionTimer = timers["wholeExecution"]
        if 
            let lll = longestLabelLength,
            let we  = wholeExecutionTimer
        {
            let prefixLength = "Timer '".count + 2
            for (timerLabel,timerValue) in Array(timers).sorted(by: { t1,t2 in t1 < t2 }) {
                if timerLabel.first! != "_" { // Ignore internal timers
                    let labelString = "Timer '\(timerLabel)':".padding(toLength: prefixLength + lll, withPad: " ", startingAt: 0)
                    let percentage = timerValue / we
                    let timerValueString = String(format: "%.3f", timerValue)
                    let percentageString = String(format: "%.0f", 100*(timerValue / we))
                    Log.debug("\(labelString)\(timerValueString)s ~ \(percentageString)%")
                }
            }
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

        func readTimeAndSystemEnergy() {
            guard 
                let anyArchitecture = runtime.architecture,
                let architecture = anyArchitecture as? ClockAndEnergyArchitecture
            else {
                FAST.fatalError("Attempt to read time and system energy, but no compatible architecture was initialized.")
            }
            runtime.measure("time", architecture.clockMonitor.readClock())
            runtime.measure("systemEnergy", Double(architecture.energyMonitor.readEnergy()))
        }

        /** Execute preBody, execute body, update measures provided by runtime, and update postBody. */
        func executeBodyAndComputeMeasures() {

            startMeasuring("beforePreBody")
            Log.debug("optimize.loop.updateMeasuresBegin")
            // When in scripted mode, block until a post to the /process endpoint
            runtime.waitForRestCallToIncrementScriptedCounter()
            // Increment the iteration measure
            iteration += 1
            // Note that one less iteration is left to be processed when in scripted mode
            runtime.decrementScriptedCounter()
            // Record values of time and energy before executing the loop body
            readTimeAndSystemEnergy()
            let systemEnergyBefore = runtime.getMeasure("systemEnergy")!
            let timeBefore = runtime.getMeasure("time")! // begin measuring latency
            stopMeasuring("beforePreBody")

            startMeasuring("preBody")
            // Run preparatory code for this iteration, e.g. to reconfigure the system using a controller
            preBody()
            stopMeasuring("preBody")
            
            startMeasuring("body")
            // Run the loop body
            body()
            stopMeasuring("body")

            startMeasuring("postBody")
            // Run wrap-up code for this iteration, e.g. to report progress to a measuring device
            postBody()
            stopMeasuring("postBody")

            startMeasuring("afterPostBody")
            // Record values of time and energy after executing the loop body
            readTimeAndSystemEnergy()
            let timeAfter = runtime.getMeasure("time")! // stop measuring latency
            let systemEnergyAfter = runtime.getMeasure("systemEnergy")! // stop measuring energy
            // Measure the iteration counter
            runtime.measure("iteration", Double(iteration))
            runtime.measure("windowSize", Double(windowSize))
            // Compute the latency and energyDelta, and if both are greater than 0, record them and their derived measures
            let latency: Double = timeAfter - timeBefore                
            let energyDelta: Double = systemEnergyAfter - systemEnergyBefore
            if latency > 0.0 {
                runningTime += latency
                runtime.measure("latency", latency) // latency in seconds
                runtime.measure("runningTime", runningTime) // running time in seconds
                runtime.measure("performance", 
                    computeDerivedMeasure("performance", runtimeMeasureValueGetter)) // seconds per iteration
            }
            else {
                Log.debug("Zero time spent in this iteration. The performance measure cannot be computed and won't be updated. The latency and runningTime measures won't be updated.")
            }
            if energyDelta > 0.0 {
                energy += energyDelta
                runtime.measure("energyDelta", energyDelta) // energy per iteration
                runtime.measure("energy", energy) // energy since application started or was last reset
            }
            else {
                Log.debug("Zero energy spent in this iteration. The energyDelta and energy measures won't be updated.")
            }
            if latency > 0.0 && energyDelta > 0.0 {
                runtime.measure("powerConsumption", 
                    computeDerivedMeasure("powerConsumption", runtimeMeasureValueGetter)) // rate of energy
            }
            else {
                Log.debug("Zero time and or energy spent in this iteration (latency: \(latency), energyDelta: \(energyDelta)). The powerConsumption measure cannot be computed and won't be updated.")
            }
            Log.debug("optimize.loop.updateMeasuresEnd")
            stopMeasuring("afterPostBody")

        }

        // Wait for the system measures to be read
        while runtime.getMeasure("time") == nil || runtime.getMeasure("systemEnergy") == nil {
            readTimeAndSystemEnergy()
            usleep(10000) // sleep 10ms
        }

        startMeasuring("wholeExecution")
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
        stopMeasuring("wholeExecution")

        logTimingReport()
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
                FAST.fatalError("Invalid knob table found at '\(knobTablePath)'.")
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
                                knobSettings.apply(runtime: runtime)
                            }) 
                        {
                            startTime = ProcessInfo.processInfo.systemUptime // reset, in case something paused execution between iterations
                            routine() // execute the routine (body of the optimize constuct)
                        }

                        // Output profile entry as line in knob table
                        func serializeKnobValue(_ v : Any) -> String {
                            switch v {
                                case let vString as String:
                                    return "<\(vString)>"
                                default:
                                    return "\(v)"
                            }
                        }
                        let knobValues = knobNames.map{ serializeKnobValue(knobSettings.settings[$0]!) }
                        let knobTableLine = makeRow(id: i, rest: knobValues)
                        knobTableOutputStream.write(knobTableLine, maxLength: knobTableLine.characters.count)

                        /** Obtains a measure's total average from the measuringDevice */
                        func runtimeMeasureTotalAverageGetter(_ measureName: String) -> Double {
                            if let measureStats = measuringDevice.stats[measureName] {
                                return measureStats.totalAverage
                            }
                            else {
                                FAST.fatalError("No statistics for measure '\(measureName)' available in measuring device. Valid measures are: \(measuringDevice.stats.keys).")
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
            FAST.fatalError("Cannot trace since either the application or the architecture are not emulatable.")
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
            FAST.fatalError("Can not encode tracing database as JSON: \(dicts).")
        }
        withOpenFile(atPath: profileOutputPrefix + ".trace.json") {
            (jsonOutputStream: Foundation.OutputStream) in
                jsonOutputStream.write(String(decoding: encodedDicts, as: UTF8.self), maxLength: encodedDicts.count)
        }

    }

    func run(model: Model?, intent: IntentSpec, missionLength: UInt64) {

        Log.info("Running optimize scope \(id).")

        // By default, use the passed controller model but, if the machine learning
        // module is enabled, request a model from it and use that instead.
        let model = runtime.executeWithMachineLearning 
                  ? runtime.requestInitialModelFromMachineLearning(id: id, activeIntent: intent, originalModel: model)
                  : model

        func initializeMeasuresAndGetInitialKnobSettings() -> KnobSettings {

            resetMeasures()

            switch runtime.runtimeKnobs.applicationExecutionMode.get() {
                
                case .Adaptive:

                    if let controllerModel = model {

                        // Run the application in a fixed, known configuration for the first window
                        let initialConfiguration = controllerModel.configurations[0] // Always configuration 0 since FASTController assumes the model is sorted by the constraint measure
                        runtime.controller = ConstantController(knobSettings: initialConfiguration.knobSettings) 
                        runtime.setIntent(intent)
                        runtime.setModel(name: intent.name, currentModel: controllerModel, untrimmedModel: controllerModel)

                        // Compute initial schedule that meets the active intent, by using the measure values of
                        // the reference configuration as an estimate of the first measurements.
                        let measureValuesOfInitialConfiguration = Dictionary(Array(zip(initialConfiguration.measureNames, initialConfiguration.measureValues)))
                        
                        // Initialize measures
                        for measure in intent.measures {
                            if let measureValue = measureValuesOfInitialConfiguration[measure] {
                                runtime.measure(measure, measureValue)
                            }
                            else {
                                FAST.fatalError("Invalid model: missing values for measure '\(measure)'.")
                            }
                        }

                        return initialConfiguration.knobSettings

                    }
                    else {
                        FAST.fatalError("Attempt to execute in adaptive mode using controller with undefined model.")
                    }

                case .NonAdaptive:

                    // Initialize the constant controller with the reference configuration from the intent
                    let initialKnobSettings = intent.referenceKnobSettings()
                    runtime.controller = ConstantController(knobSettings: initialKnobSettings) 
                    runtime.setIntent(intent)        
                    runtime.setModel(name: intent.name, currentModel: model!, untrimmedModel: model!)

                    // Initialize measures
                    for measure in intent.measures {
                        runtime.measure(measure, 0.0)
                    }

                    return initialKnobSettings
                
                default:
                    
                    FAST.fatalError("Attempt to execute in unsupported execution mode: \(runtime.runtimeKnobs.applicationExecutionMode.get()).")

            }
        }

        // For the first window, the runtime will execute in the initial configuration 
        // (the initial value of currentKnobSettings), to obtain measures for this 
        // configuration that can be used to correctly initialize the controller, at
        // the first iteration of the second window.
        var currentKnobSettings = initializeMeasuresAndGetInitialKnobSettings()
        currentKnobSettings.apply(runtime: runtime)
        var lastKnobSettings = currentKnobSettings
        runtime.schedule = Schedule(constant: currentKnobSettings)
        runtime.measure("currentConfiguration", Double(currentKnobSettings.kid)) // The id of the configuration given in the knobtable

        // Initialize measuring device, that will update measures based on the samplingPolicy
        let measuringDevice = MeasuringDevice(samplingPolicy, windowSize, intent.measures, runtime)
        runtime.measuringDevices[id] = measuringDevice

        // Send status messages to the test harness on a separate thread using this queue
        let sendStatusQueue = DispatchQueue(label: "sendStatus")

        // Output status to console if enough time has elapsed, and unless proteus_runtime_suppressStatus is 'true'
        var timeOfLastStatus = NSDate().timeIntervalSince1970
        let minimumSecondsBetweenStatuses = initialize(type: Double.self, name: "minimumSecondsBetweenStatuses", from: key, or: 0.0)
        let suppressStatus                = initialize(type: Bool.self,   name: "suppressStatus",                from: key, or: false)

        // Start the input processing loop
        loop( iterations: missionLength
            , preBody: {

                // If this is the first iteration of any subsequent window, or if the schedule 
                // has been invalidated (e.g. by the /perturb endpoint), request a new schedule.
                if (iteration > 0 && iteration % windowSize == 0) || runtime.schedule == nil {

                    // Before the first iteration of the second window, runtime.controller is always
                    // a ConstantController. If running in Adaptive mode, replace this with the right 
                    // adaptive controller.
                    if 
                        runtime.runtimeKnobs.applicationExecutionMode.get() == .Adaptive &&
                        runtime.controller is ConstantController
                    {
                        // Initialize the controller with the knob-to-mesure model, intent and window size
                        guard let controllerModel = model else {
                            FAST.fatalError("Attempt to initialize adaptive controller with undefined model.")
                        }
                        runtime.initializeController(controllerModel, intent, windowSize)
                    }

                    // If the controller deems the model is bad, and if online model updates
                    // have been enabled, request a new model from the machine learning module.
                    // NOTE: This will only happen if the schedule has not been set to nil by a 
                    // call to the /perturb end-point.
                    if let schedule = runtime.schedule {
                        let shouldRequestNewModel = schedule.oscillating
                        if runtime.executeWithMachineLearning && shouldRequestNewModel {
                            Log.verbose("Requesting new model from machine learning module at iteration \(iteration).")
                            let lastWindowConfigIds = (0..<windowSize).map { schedule[$0].kid }
                            let lastWindowMeasures = measuringDevice.stats.mapValues { $0.lastWindow }
                            runtime.updateModelFromMachineLearning(id, lastWindowConfigIds, lastWindowMeasures)
                        }   
                    }

                    Log.debug("Computing schedule from window averages: \(measuringDevice.windowAverages()).")
                    runtime.schedule = runtime.controller.getSchedule(runtime.intents[id]!, measuringDevice.windowAverages())

                }
                startMeasuring("preBody > knobActuation")
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
                stopMeasuring("preBody > knobActuation")
            }
            , postBody: {
                
                startMeasuring("postBody > reportProgress")
                measuringDevice.reportProgress()
                stopMeasuring("postBody > reportProgress")
                
                startMeasuring("postBody > logStatus")
                // Send a status to the test harness if enough time has elapsed since the last status
                let timeNow = NSDate().timeIntervalSince1970
                if !suppressStatus && timeNow >= timeOfLastStatus + minimumSecondsBetweenStatuses {
                    let statusDictionary = runtime.statusDictionary()
                    Log.debug("\nCurrent status: \(convertToJsonSR4783(from: statusDictionary ?? [:])).\n")
                    if runtime.executeWithTestHarness {
                        // sendStatusQueue.async {
                        //     // FIXME handle error from request
                        //     let _ = RestClient.sendRequest(to: "status", withBody: statusDictionary)
                        // }
                    }
                    timeOfLastStatus = timeNow
                }
                stopMeasuring("postBody > logStatus")

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
            var model: Model
            if let modelFromTestHarness = ips.model {
                Log.info("Received model as part of the inialization parameters.")
                model = modelFromTestHarness
            }
            else {
                Log.info("No model received as part of the inialization parameters, will read the model from file.")
                model = runtime.readModelFromFile(id, intent: ips.initialConditions.missionIntent)!
            }

            Log.debug("Using initialization parameters from test harness: \(ips.asDict()).")

            Log.info("Posting to TH/initialized.")
            // FIXME handle error from request
            let _ = RestClient.sendRequest(to: "initialized")

            runtime.setScenarioKnobs(accordingTo: ips.initialConditions)
            
            let applicationExecutionMode: ApplicationExecutionMode = ips.adaptationEnabled ? .Adaptive : .NonAdaptive
            Log.verbose("Setting application execution model to \(applicationExecutionMode).")
            runtime.runtimeKnobs.applicationExecutionMode.set(applicationExecutionMode)

            run(model: model, intent: ips.initialConditions.missionIntent, missionLength: ips.initialConditions.missionLength)

        }
        else {
            FAST.fatalError("Invalid initalization parameters received from /ready endpoint.")
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
                            let missionLength      = initialize(type: UInt64.self, name: "missionLength"     , from: key)
                        {
                            run(model: model, intent: intent, missionLength: missionLength)
                        }
                        else {
                            FAST.fatalError("The missionLength parameter (mandatory for Adaptive execution) could not be initialized.")
                        }

                    } else {
                        FAST.fatalError("No model loaded for optimize scope '\(id)'. Cannot execute application in application execution mode \(runtime.runtimeKnobs.applicationExecutionMode.get()).")
                    }

                case .NonAdaptive:

                    if let model = runtime.readModelFromFile(id, intent: intent) {

                        if 
                            let missionLength = initialize(type: UInt64.self, name: "missionLength", from: key)
                        {
                            run(model: model, intent: intent, missionLength: missionLength)
                        }
                        else {
                            FAST.fatalError("The missionLength parameter (mandatory for NonAdaptive execution) could not be initialized.")
                        }

                    } else {
                        FAST.fatalError("No model loaded for optimize scope '\(id)'. Cannot execute application in application execution mode \(runtime.runtimeKnobs.applicationExecutionMode.get()).")
                    }
            
                default:

                    FAST.fatalError("Attempt to execute in unsupported execution mode: \(runtime.runtimeKnobs.applicationExecutionMode.get()).")
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
