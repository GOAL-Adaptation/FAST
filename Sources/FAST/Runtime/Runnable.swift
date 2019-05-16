import Foundation
import LoggerAPI
import HeliumLogger

class Runnable: Application, EmulateableApplication, StreamApplication {
    class ApplicationKnobs: TextApiModule {
        let name = "applicationKnobs"
        var subModules = [String : TextApiModule]()

        init(submodules: [TextApiModule]) {
            for module in submodules {
              self.addSubModule(newModule: module)
            }
        }
    }

    let name: String
    var subModules = [String : TextApiModule]()
    let reinit: (() -> Void)?

    /** Initialize the application */
    required init(name: String, knobs: [TextApiModule], streamInit: (() -> Void)?) {

        self.name = name
        self.reinit = streamInit

        // Check that a compatible version of Swift was used to compile the application

        #if !swift(>=4.1) || swift(>=4.2)
            print("Incompatible Swift version detected. Please compile using 4.1 <= Swift <= 4.1.2.")
            exit(1)
        #endif

        // Check for unknown environment variables (starting with "proteus")

        let knownParameters = [

            ["proteus","runtime","logLevel"],
            ["proteus","runtime","logToStandardError"],
            ["proteus","runtime","logToMemory"],
            
            ["proteus","runtime","missionLength"],
            ["proteus","runtime","profileOutputPrefix"],

            ["proteus","runtime","randomSeed"],
            
            ["proteus","runtime","weightForFeedbackControl"],
            
            ["proteus","emulator","emulationDatabaseType"],
            ["proteus","emulator","database","db"],
            ["proteus","emulator","database","readingMode"],
            
            ["proteus","client","rest","serverProtocol"],
            ["proteus","client","rest","serverAddress"],
            ["proteus","client","rest","serverPort"],
            
            ["proteus","runtime","port"],
            ["proteus","runtime","profilingPort"],
            ["proteus","runtime","address"],
            
            ["proteus","runtime","applicationExecutionMode"],

            ["proteus","runtime","executeWithMachineLearning"],
            ["proteus","runtime","executeWithTestHarness"],
            ["proteus","runtime","sendStatusToTestHarness"],
            ["proteus","runtime","detailedStatusMessages"],
            ["proteus","runtime","suppressStatus"],
            ["proteus","runtime","minimumSecondsBetweenStatuses"],
            ["proteus","runtime","outputMeasurePredictions"],
            ["proteus","runtime","collectDetailedStatistics"],

            ["proteus","armBigLittle","policy"],
            ["proteus","armBigLittle","availableBigCores"],
            ["proteus","armBigLittle","availableLittleCores"],
            ["proteus","armBigLittle","maximalBigCoreFrequency"],
            ["proteus","armBigLittle","maximalLittleCoreFrequency"],
            ["proteus","armBigLittle","utilizedBigCores"],
            ["proteus","armBigLittle","utilizedLittleCores"],

            ["proteus","xilinxZcu","policy"],
            ["proteus","xilinxZcu","availableCores"],
            ["proteus","xilinxZcu","availableCoreFrequency"],
            ["proteus","xilinxZcu","utilizedCores"],
            ["proteus","xilinxZcu","utilizedCoreFrequency"],

            ["proteus","architecture","linuxDvfsGovernor"]

        ]
        
        let knownParameterStrings = knownParameters.map{ $0.joined(separator: "_") }

        let proteusEnvironment = ProcessInfo.processInfo.environment.keys.filter{ $0.starts(with: "proteus_") }

        let unknownParameters = proteusEnvironment.filter{ !knownParameterStrings.contains($0) }

        if unknownParameters.count > 0 {
            let unknownParametersAndTheirValues = 
                Array(unknownParameters.map{ p in (p, ProcessInfo.processInfo.environment[p] ?? "<UNASSIGNED>") })
                    .map{ "\($0.0)=\($0.1)" }.joined(separator: ", ")
            FAST.fatalError("Unknown environment variables encountered: \(unknownParametersAndTheirValues).")
        }

        // Initialize and register application knobs

        let applicationKnobs = ApplicationKnobs(submodules: knobs)
        self.addSubModule(newModule: applicationKnobs)

    }

    /** Look up the id (in the database) of the current application configuration. */
    func getCurrentConfigurationId(database: Database) -> Int {
        return database.getCurrentConfigurationId(application: self)
    }

    func initializeStream() {
        reinit?()
    }
}

fileprivate var runtime: Runtime!

/** Register a dynamically created application knob, that is, one instantiated from inside the optimize loop's body. */
func registerApplicationKnob(_ knob: TextApiModule) {
    // Knobs that are instantiated outside the optimize loop are registered in 
    // the Runnable initializer, and will thus be skipped in the follwing if-let
    if 
        let k = knob as? IKnob,
        let r = runtime,
        let application = r.application,
        let applicationAsRunnable = application as? Runnable,
        let applicationKnobs = applicationAsRunnable.subModules["applicationKnobs"]
    {
        r.knobSetters[knob.name] = k.setter
        applicationKnobs.addSubModule(newModule: knob)
    }
}

/** 
 * Set application knob model filter, stored in runtime.modelFilters[], which are applied
 * to contoller models when the controller is initialized.
 * Used to implement toggling of control for knobs, by:
 *  - filtering configurations that match an array of knob values (to "restrict the knob"),
 *  - including configurations for all values of this knob (to "enable control for the knob").
 */
func setApplicationKnobModelFilter(forKnob knobName: String, to targetKnobValues: [Any]) {
    guard let r = runtime else {
        FAST.fatalError("Attempt to set model filter for knob '\(knobName)' before runtime is initialized.")
    }
    guard let targetKnobIntValues = targetKnobValues as? [Int] else {
        FAST.fatalError("Currently application knob filters must consist only of Int values. Offending filter: \(targetKnobValues).")
    }
    // Check if the previous knob values are the same as the target ones, to exit early
    if 
        let previousKnobAnyValues = r.knobRanges[knobName],
        let previousKnobIntValues = previousKnobAnyValues as? [Int],
        targetKnobIntValues == previousKnobIntValues
    {
        // Filter is the same as the current one, no need to change anything
        return
    }
    r.knobRanges[knobName] = targetKnobValues
    let filterName = "filter values for knob \(knobName)"
    // If targetKnobValue is empty, clear the filter for this knob
    if targetKnobValues.isEmpty {
        r.modelFilters[filterName] = nil // Model will not be trimmed w.r.t. this knob in Runtime.initializeController()
        Log.debug("Clearing model filter for knob '\(knobName)'.")
    }
    // Otherwise, set a filter that leaves only configurations whose value for this knob is in targetKnobValue
    else {
        Log.debug("Setting model filter for knob '\(knobName)' based on value array '\(targetKnobValues)'.")
        r.modelFilters[filterName] = { (someConfiguration: Configuration) in 
            if let someConfigurationsKnobValue = someConfiguration.knobSettings.settings[knobName] {
                if let cv = someConfigurationsKnobValue as? (Int) {
                    // Check if cv is in targetKnobValues
                    for v in targetKnobValues {
                        if (v as! Int) == cv {
                            return true
                        }
                    }
                    return false
                } 
                else {
                    FAST.fatalError("Knob '\(knobName)' in model has value '\(someConfigurationsKnobValue)' of unsupported type: '\(type(of: someConfigurationsKnobValue))'. Can not set application knob filter.")
                }
            }
            else {
                FAST.fatalError("Knob '\(knobName)' is missing from model. Can not set application knob filter.")
            }
        }
    }
    r.perturbationOccurred = true
}

func setIntentModelFilter(_ spec: IntentSpec) {
    guard let r = runtime else {
        FAST.fatalError("Attempt to set model filter for the follwing intent before runtime is initialized: '\(spec)'.")
    }
    let filterName = "filter values for intent \(spec.name)"
    Log.debug("Setting model filter for intent '\(spec.name)' based on intent specification: \(spec).")
    r.modelFilters[filterName] = { $0.isIn(intent: spec) }
    r.perturbationOccurred = true
} 

func getKnobRange(knobName: String) -> [Any] {
    guard let r = runtime else {
        FAST.fatalError("Attempt to get range for knob '\(knobName)' before runtime is initialized.")
    }
    return r.knobRanges[knobName] ?? []
}

@discardableResult public func measure(_ name: String, _ value: Double) -> Double {
    return runtime.measure(name, value)
}

class LogOutputStream: TextOutputStream {
    let inMemory: Bool
    let stream: FileHandle
    var buffer: [Data]
    init(toStream stream: FileHandle, inMemory: Bool) {
        self.stream = stream
        self.inMemory = inMemory
        self.buffer = [Data]()
    }
    func write(_ text: String) {
        guard let data = text.data(using: String.Encoding.utf8) else { return }
        if inMemory {
            buffer.append(data)
        }
        else {
            self.stream.write(data)
        }
    }
    func flush() {
        if inMemory {
            for logLine in buffer {
                self.stream.write(logLine)
            }
            self.buffer = [Data]()
        }
    }
}
class StandardOutput: LogOutputStream {
    init(inMemory: Bool) {
        super.init(toStream: FileHandle.standardOutput,inMemory: inMemory)
    }
}
class StandardError: LogOutputStream {
    init(inMemory: Bool) {
        super.init(toStream: FileHandle.standardError, inMemory: inMemory)
    }
}

public func optimize(
    _ id: String,
    _ knobs: [TextApiModule],
    usingRuntime providedRuntime: Runtime? = nil,
    architecture: String = "XilinxZcu",
    streamInit: (() -> Void)? = nil,
    until shouldTerminate: @escaping @autoclosure () -> Bool = false,
    across windowSize: UInt32 = 20,
    samplingPolicy: SamplingPolicy = ProgressSamplingPolicy(period: 1),
    _ routine: @escaping () -> Void)
{

    // Initialize the logger
    let logLevel = initialize(type: LoggerMessageType.self, name: "logLevel", from: ["proteus","runtime"], or: .verbose)
    let logToStandardError = initialize(type: Bool.self, name: "logToStandardError", from: ["proteus","runtime"], or: false)
    let logToMemory = initialize(type: Bool.self, name: "logToMemory", from: ["proteus","runtime"], or: false)
    
    let outputStream = logToStandardError
                     ? StandardError(inMemory: logToMemory)
                     : StandardOutput(inMemory: logToMemory)

    HeliumStreamLogger.use(logLevel, outputStream: outputStream)

    // initialize runtime
    runtime = providedRuntime ?? Runtime.newRuntime()

    // initialize application and add it to runtime
    let app = Runnable(name: id, knobs: knobs, streamInit: streamInit)
    runtime.registerApplication(application: app)

    // configure runtime
    runtime.initializeArchitecture(name: architecture)

    // run stream init if needed
    app.initializeStream()

    // start the actual optimization
    optimize(app.name, runtime, until: shouldTerminate, across: windowSize, samplingPolicy: samplingPolicy, routine)

    // Flush the log if it was buffered in memory
    if logToMemory {
        outputStream.flush()
    }
}
