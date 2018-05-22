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
            // Measure the iteration counter
            runtime.measure("iteration", Double(iteration))
            runtime.measure("windowSize", Double(windowSize))
            // Compute the latency, and if that is greater than 0, record derived measures
            let latency: Double = runtime.getMeasure("time")! - timeBefore
            if latency > 0.0 {
                
                let systemEnergyAfter = runtime.getMeasure("systemEnergy")!
                let energyDelta: Double = systemEnergyAfter - systemEnergyBefore
                
                runningTime += latency
                energy += energyDelta

                runtime.measure("latency", latency) // latency in seconds
                runtime.measure("energyDelta", energyDelta) // energy per iteration
                runtime.measure("energy", energy) // energy since application started or was last reset
                runtime.measure("runningTime", runningTime) // running time in seconds
                runtime.measure("performance", 1.0 / latency) // seconds per iteration
                runtime.measure("powerConsumption", energyDelta / latency) // rate of energy
                // If running in Adaptive mode, the energyLimit is defined
                if let theEnergyLimit = runtime.energyLimit {
                    runtime.measure("energyRemaining", Double(theEnergyLimit) - energy)
                }                
            }
            else {
                Log.debug("Zero time passed between two measurements of time. The performance and powerConsumption measures cannot be computed.")
            }
            Log.debug("optimize.loop.updateMeasuresEnd")
        }

        if let i = iterations {
            Log.verbose("Starting execution bounded by missionLength parameter to \(i) iterations.")
            while !shouldTerminate() && !runtime.shouldTerminate && UInt64(runtime.getMeasure("iteration")!) < i {
                executeBodyAndComputeMeasures()                
            
            }
            Log.verbose("Ending execution bounded by missionLength parameter to \(i) iterations.")
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
        let inProcessProfiling  = initialize(type: Bool.self,   name: "inProcessProfiling",  from: key, or: true)

        withOpenFile(atPath: profileOutputPrefix + ".knobtable") { (knobTableOutputStream: Foundation.OutputStream) in
            withOpenFile(atPath: profileOutputPrefix + ".measuretable") { (measureTableOutputStream: Foundation.OutputStream) in
                withOpenFile(atPath: profileOutputPrefix + ".variancetable") { (varianceTableOutputStream: Foundation.OutputStream) in

                    let knobSpace = intent.knobSpace(exhaustive: exhaustive)
                    let knobNames = Array(knobSpace[0].settings.keys).sorted()
                    let measureNames = Array(Set(intent.measures + runtime.runtimeAndSystemMeasures)).sorted()

                    func makeRow(id: Any, rest: [Any]) -> String {
                        return "\(id)\(rest.reduce( "", { l,r in "\(l),\(r)" }))\n"
                    }

                    // Output headers for tables
                    let knobTableHeader = makeRow(id: "id", rest: knobNames)
                    knobTableOutputStream.write(knobTableHeader, maxLength: knobTableHeader.count)
                    let measureTableHeader = makeRow(id: "id", rest: measureNames)
                    measureTableOutputStream.write(measureTableHeader, maxLength: measureTableHeader.count)
                    let varianceTableHeader = makeRow(id: "id", rest: measureNames)
                    varianceTableOutputStream.write(varianceTableHeader, maxLength: varianceTableHeader.count)

                    for i in 0 ..< knobSpace.count {

                        let knobSettings = knobSpace[i]
                        Log.info("Start profiling of configuration: \(knobSettings.settings).")
                        knobSettings.apply(runtime: runtime)

                        // Profile configuration by running the loop in the same process
                        if inProcessProfiling {
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

                            // Output profile entry as line in measure table
                            let measureValues = measureNames.map{ measuringDevice.stats[$0]!.totalAverage }
                            let measureTableLine = makeRow(id: i, rest: measureValues)
                            measureTableOutputStream.write(measureTableLine, maxLength: measureTableLine.characters.count)

                            // Output profile entry as line in variance table
                            let varianceValues = measureNames.map{ measuringDevice.stats[$0]!.totalVariance }
                            let varianceTableLine = makeRow(id: i, rest: varianceValues)
                            varianceTableOutputStream.write(varianceTableLine, maxLength: varianceTableLine.characters.count)

                        }
                        // Profile configuration by starting a new application process
                        else {

                            let task = Process()
                            task.launchPath = "/usr/bin/make"
                            task.arguments = [
                                "run-scripted",
                                "proteus_runtime_applicationExecutionMode=NonAdaptive",
                                "proteus_runtime_missionLength=\(profileSize)",
                                // Override the default REST server port to avoid clash with the current FAST application instance
                                "proteus_runtime_port=\(runtime.profilingRestServerPort)"
                            ]
                            task.launch()

                            let profilingFastInstanceAddress = "127.0.0.1"
                            waitUntilUp(endpoint: "alive", host: profilingFastInstanceAddress, port: runtime.profilingRestServerPort, method: .get, description: "Profling REST")

                            /** From knobSettings.settings, which is a dictionary of (name:value) pairs,
                            *   for example, ["threshold": 200000, "utilizedCoreFrequency": 300, "step": 1, "utilizedCores": 1]
                            *   Create an array of dictionaries, for example:
                            * [
                            *  ["name": "threshold", "value": 20000000], 
                            *  ["name": "utilizedCoreFrequency", "value":300],
                            *  ["name": "step", "value" 1].
                            *  ["name": "utilizedCores", "value": 1]
                            * ]
                            */ 
                            var appSysConfig = [Any]()
                            for (knobName, knobVal) in knobSettings.settings {
                                var knobNameKnobValDict = [String:Any]()
                                knobNameKnobValDict["name"]  = knobName
                                knobNameKnobValDict["value"] = knobVal
                                appSysConfig.append(knobNameKnobValDict)
                            }

                            RestClient.sendRequest( to: "fixConfiguration"
                                , at         : profilingFastInstanceAddress
                                , onPort     : runtime.profilingRestServerPort
                                , withBody   : ["knobSettings": appSysConfig]
                                , logErrors  : true
                            )

                            RestClient.sendRequest( to: "process"
                                , at         : profilingFastInstanceAddress
                                , onPort     : runtime.profilingRestServerPort
                                , withBody   : ["inputs": profileSize-1]
                                , logErrors  : true
                            )

                            let statusAtEndOfExecution = 
                                RestClient.sendRequest( to: "query"
                                    , at         : profilingFastInstanceAddress
                                    , onPort     : runtime.profilingRestServerPort
                                    , withMethod : .get
                                    , logErrors  : true
                                )

                            RestClient.sendRequest( to: "terminate"
                                , at         : profilingFastInstanceAddress
                                , onPort     : runtime.profilingRestServerPort
                                , logErrors  : true
                            )

                            task.waitUntilExit() // waits for call to complete

                            if 
                                let maybeStatusArgumentsDict = statusAtEndOfExecution,
                                let statusArgumentsDictAny = maybeStatusArgumentsDict["arguments"],
                                let statusArgumentsDict = statusArgumentsDictAny as? [String: Any],
                                let measureStatistics = statusArgumentsDict["measureStatistics"] as? [String: Any] 
                            {
                                var measureTableLine = "\(i)"
                                var varianceTableLine = "\(i)"
                                for measureName in measureNames {
                                    let measureNameStats = measureStatistics[measureName] as! [String: Double]
                                    let measureTotalAverage = measureNameStats["totalAverage"]!
                                    let measureTotalVariance = measureNameStats["totalVariance"]!
                                    measureTableLine += ",\(measureTotalAverage)"
                                    varianceTableLine += ",\(measureTotalVariance)"
                                }
                                measureTableLine += "\n"
                                varianceTableLine += "\n"

                                // Output profile entries as lines in measure table and variance table
                                measureTableOutputStream.write(measureTableLine, maxLength: measureTableLine.count)
                                varianceTableOutputStream.write(varianceTableLine, maxLength: varianceTableLine.count)

                                // Output profile entry as line in knob table
                                let knobValues = knobNames.map{ knobSettings.settings[$0]! }
                                let knobTableLine = makeRow(id: i, rest: knobValues)
                                knobTableOutputStream.write(knobTableLine, maxLength: knobTableLine.count)
                            }
                            else {
                                Log.error("Unable to extract profile entry for configuration \(i) from status message: \(statusAtEndOfExecution).")
                                fatalError()
                            }

                        }

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
        
        guard let myApp = runtime.application as? EmulateableApplication, let myArch = runtime.architecture as? EmulateableArchitecture else {
            fatalError("Cannot trace since either the application or the architecture are not emulatable.")
        }

        /// --- Begin DictDatabase code
        // Initialize dictionaries for JSON database
        let applicationId                    = 0 // JSON database only supports a single application
        let applicationInputID               = runtime.applicationInputId // JSON database only supports a single input stream
        var getCurrentAppConfigurationIdDict = [ KnobSettings                         : Int                             ]()
        var getCurrentSysConfigurationIdDict = [ KnobSettings                         : Int                             ]()
        var tracedConfigurations             = [ DictDatabase.ProfileEntryId                                            ]()
        var readDeltaDict                    = [ DictDatabase.ProfileEntryIterationId : DictDatabase.TimeAndEnergyDelta ]()
        /// --- End DictDatabase code

        // step 1: Emit SQL to insert application and architecture properties based on an intent specification.
        let applicationAndArchictectureInsertion
        = emitScriptForApplicationAndArchitectureInsertion(
              application    : myApp
            , warmupInputNum : warmupInputNum
            , architecture   : myArch
            , intent         : intent)

        // step 2.1: Emit SQL to insert application input stream
        let inputStreamName = myApp.name + "_inputStream" // TODO: must pass in input stream name
        let appInputStreamInsertion
        = emitScriptForApplicationInputStreamInsertion(applicationName: myApp.name, inputStreamName: inputStreamName)

        // step 2.2: Emit SQL to insert job log parameters (if any).
        let jobLogParamInsertion
        = emitScriptForJobLogParameterInsertion(  // TODO: must pass in energyOutlier, tapeNoise and timeOutlier
            applicationName: myApp.name,
            energyOutlier  : energyOutlier,
            tapeNoise      : tapeNoise,
            timeOutlier    : timeOutlier)

        var insertionScript =
        "PRAGMA foreign_keys = 'off'; BEGIN;"
        + "\n" + applicationAndArchictectureInsertion  // step 1
        + "\n" + appInputStreamInsertion               // step 2.1
        + "\n" + jobLogParamInsertion                  // step 2.2

        // Number of inputs to process when profiling a configuration
        let defaultProfileSize: UInt64 = UInt64(1000)
        let profileSize = initialize(type: UInt64.self, name: "missionLength", from: key, or: defaultProfileSize)
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
        Log.debug("Tracing based on reference application configuration space of size \(knobAppRefSpace.count): \(knobAppRefSpace).")

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
        Log.debug("Tracing based on reference system configuration space of size \(knobSysRefSpace.count): \(knobSysRefSpace).")

        // Compute knobRefSpace = knobAppRefSpace union knobSysRefSpace
        var knobRefSpace = knobAppRefSpace
        for knobSettings in knobSysRefSpace {
            if !knobAppRefSpace.contains(knobSettings) { // Do not duplicate the all-reference configuration
                knobRefSpace.append(knobSettings)
            }
        }

        let pureReferenceConfiguration          = Set(knobAppRefSpace).intersection(knobSysRefSpace).first! // Extract the element of the singleton 
        // The id of an application configuration KnobSettings as its position in the knobSysRefSpace
        let referenceApplicationConfigurationId = knobSysRefSpace.index(of: pureReferenceConfiguration)!
        // The id of a system configuration KnobSettings as its position in the knobAppRefSpace
        let referenceSystemConfigurationId      = knobAppRefSpace.index(of: pureReferenceConfiguration)!

        Log.debug("Tracing based on reference configuration space of size \(knobRefSpace.count) with pure-refernce configuration '\(pureReferenceConfiguration)': \(knobRefSpace).")

        // Trace only those configurations in knobRefSpace:
        for i in 0 ..< knobRefSpace.count {

            resetMeasures()

            // Initialize measuring device, that will update measures at every input
            let measuringDevice = MeasuringDevice(ProgressSamplingPolicy(period: 1), windowSize, intent.measures, runtime)
            runtime.measuringDevices[id] = measuringDevice

            let knobSettings = knobRefSpace[i]
            Log.info("Start tracing of configuration: \(knobSettings.settings).")
            knobSettings.apply(runtime: runtime)
            if let streamingApplication = runtime.application as? StreamApplication {
                    streamingApplication.initializeStream()
            }

            /// --- Begin DictDatabase code
            // The id of an application configuration KnobSettings as its position in the knobSysRefSpace
            let applicationConfigurationId = knobSysRefSpace.index(of: knobSettings) ?? referenceApplicationConfigurationId
            // The id of a system configuration KnobSettings as its position in the knobAppRefSpace
            let systemConfigurationId      = knobAppRefSpace.index(of: knobSettings) ?? referenceSystemConfigurationId
            // Register the profileEntryId of the current knobSettings in tracedConfigurations
            let profileEntryId = 
                DictDatabase.ProfileEntryId( 
                      applicationConfigurationId : applicationConfigurationId
                    , applicationInputId         : applicationInputID
                    , systemConfigurationId      : systemConfigurationId
                    )
            tracedConfigurations.append(profileEntryId)
            // Assign an ID to the current application configuration and insert that into getCurrentAppConfigurationIdDict
            let appKnobs = myApp.getStatus()!["applicationKnobs"] as! [String : Any]
            let appKnobSettings = KnobSettings(kid: -1, DictDatabase.unwrapKnobStatus(knobStatus: appKnobs))
            if getCurrentAppConfigurationIdDict[appKnobSettings] == nil {
                // The id of an application configuration KnobSettings as its position in the knobSysRefSpace
                getCurrentAppConfigurationIdDict[appKnobSettings] = knobSysRefSpace.index(where: { $0.contains(appKnobSettings.settings) })
            }
            // Assign an ID to the current system configuration and insert that into getCurrentSysConfigurationIdDict
            let sysKnobs = myArch.getStatus()!["systemConfigurationKnobs"] as! [String : Any]
            let sysKnobSettings = KnobSettings(kid: -1, DictDatabase.unwrapKnobStatus(knobStatus: sysKnobs))
            if getCurrentSysConfigurationIdDict[sysKnobSettings] == nil {
                // The id of a system configuration KnobSettings as its position in the knobAppRefSpace
                getCurrentSysConfigurationIdDict[sysKnobSettings] = knobAppRefSpace.index(where: { $0.contains(sysKnobSettings.settings) })
            }
            /// --- End DictDatabase code

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
            var lastTime = runtime.getMeasure("time")!
            var lastEnergy = runtime.getMeasure("energy")!
            var deltaTimeDeltaEnergyInsertion = ""
            loop( iterations: profileSize
                , postBody: { measuringDevice.reportProgress() } ) 
            {
                routine()
                let time = runtime.getMeasure("time")!
                let energy = runtime.getMeasure("energy")!
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

                /// --- Begin DictDatabase code
                let profileEntryIterationId = 
                    DictDatabase.ProfileEntryIterationId(profileEntryId : profileEntryId, iteration: inputNum) 
                readDeltaDict[profileEntryIterationId] = DictDatabase.TimeAndEnergyDelta(timeDelta: deltaTime, energyDelta: deltaEnergy)
                /// --- End DictDatabase code

                lastTime = time
                lastEnergy = energy
                inputNum += 1
            }

            insertionScript +=
            "\n" + deltaTimeDeltaEnergyInsertion         // step 5
        }

        insertionScript += "\n COMMIT; PRAGMA foreign_keys = 'on';"

        // Write SQL script to file:
        let defaultProfileOutputPrefix: String = runtime.application?.name ?? "fast"
        let profileOutputPrefix = initialize(type: String.self, name: "profileOutputPrefix", from: key, or: defaultProfileOutputPrefix)
        withOpenFile(atPath: profileOutputPrefix + ".trace.sql") {
            (sqlScriptOutputStream: Foundation.OutputStream) in
                sqlScriptOutputStream.write(insertionScript, maxLength: insertionScript.count)
        }

        /// --- Begin DictDatabase code
        // Compute the IDs of the reference application and system configurations
        let referenceApplicationKnobSettings = 
            KnobSettings(kid: -1, Dictionary(intent.knobs.filter{
                appKnobs.keys.contains($0.0)
            }.map{
                (knobName: String, rangeAndReferenceValue: ([Any], Any)) in
                let (_, referenceValue) = rangeAndReferenceValue
                return (knobName, referenceValue)
            }))
        let referenceSystemKnobSettings = 
            KnobSettings(kid: -1, Dictionary(intent.knobs.filter{
                sysKnobs.keys.contains($0.0)
            }.map{
                (knobName: String, rangeAndReferenceValue: ([Any], Any)) in
                let (_, referenceValue) = rangeAndReferenceValue
                return (knobName, referenceValue)
            }))

        // Write JSON database to file:
        let dicts = DictDatabase.Dicts(
              applicationName                     : myApp.name
            , architectureName                    : myArch.name
            , inputStreamName                     : inputStreamName
            , getCurrentAppConfigurationIdDict    : getCurrentAppConfigurationIdDict
            , getCurrentSysConfigurationIdDict    : getCurrentSysConfigurationIdDict
            , referenceApplicationConfigurationId : referenceApplicationConfigurationId
            , referenceSystemConfigurationId      : referenceSystemConfigurationId
            , warmupInputs                        : warmupInputNum 
            , numberOfInputsTraced                : Int(profileSize)
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
        /// --- End DictDatabase code

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
                            let modelEnergyDeltaMaxConfiguration = modelSortedByEnergyDeltaMeasure.configurations.last
                        {
                            let modelEnergyDeltaMax = UInt64(modelEnergyDeltaMaxConfiguration.measureValues[energyDeltaMeasureIdx])

                            let energyLimit = modelEnergyDeltaMax * missionLength
                            Log.verbose("An energyLimit of \(energyLimit) was computed based on a missionLength of \(missionLength) and least energy-efficient model configuration with energyDelta \(modelEnergyDeltaMax).")

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
            let model = runtime.readModelFromFile(id)!

            Log.debug("Using initialization parameters from test harness: \(ips.asDict()).")

            Log.info("Posting to TH/initialized.")
            // FIXME handle error from request
            let _ = RestClient.sendRequest(to: "initialized")

            run(model: model, intent: ips.initialConditions.missionIntent, missionLength: ips.initialConditions.missionLength, enforceEnergyLimit: ips.initialConditions.enforceEnergyLimit)

            // FIXME handle error from request
            let _ = RestClient.sendRequest(to: "done", withBody: runtime.statusDictionary())

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

                    if let model = runtime.readModelFromFile(id) {
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
