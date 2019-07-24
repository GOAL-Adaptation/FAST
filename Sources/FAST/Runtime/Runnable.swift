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
        
        let knownParameterStrings = knownParameters.map{ (p: [String], _: String) in p.joined(separator: "_") }

        let proteusEnvironment = ProcessInfo.processInfo.environment.keys.filter{ $0.starts(with: "proteus_") }

        let unknownParameters = proteusEnvironment.filter{ !knownParameterStrings.contains($0) }

        if unknownParameters.count > 0 {
            let unknownParametersAndTheirValues = 
                Array(unknownParameters.map{ p in (p, ProcessInfo.processInfo.environment[p] ?? "<UNASSIGNED>") })
                    .map{ "\($0.0)=\($0.1)" }.joined(separator: ", ")
            FAST.fatalError(
                "Unknown environment variables encountered: \(unknownParametersAndTheirValues).\n\n" + 
                "Available parameters are:\n\n" +
                knownParameters.map{ 
                    (p: [String], help: String) in 
                    p.joined(separator: "_") + "\n\t" + help 
                }.joined(separator: "\n\n")
            )
        }

        // Initialize and register application knobs

        let applicationKnobs = ApplicationKnobs(submodules: knobs)
        self.addSubModule(newModule: applicationKnobs)

    }

    let knownParameters = [

        (["proteus","runtime","logLevel"], 
            "one of [Error, Info, Verbose (default), Debug]."),
        (["proteus","runtime","logToStandardError"],
            "one of [true, false (default)]."),
        (["proteus","runtime","logToMemory"],
            "one of [true, false (default)], when true, true, log messages are not written to the output/error stream until the end of execution, which reduces overhead."),
        
        (["proteus","runtime","missionLength"],
            "Int, defaults to 1000."),
        (["proteus","runtime","profileOutputPrefix"],
            "String, defaults to application name (\"fast\" if that is undefined)."),

        (["proteus","runtime","randomSeed"],
            "Int, defaults to 0."),
        
        (["proteus","runtime","weightForFeedbackControl"],
            "Double, defaults to 0.1."),
        
        (["proteus","emulator","emulationDatabaseType"],
            "one of [Dict (default)]."),
        (["proteus","emulator","database","db"],
            "String (file name of database)"),
        (["proteus","emulator","database","readingMode"],
            "one of [Statistics, Tape]."),
        
        (["proteus","client","rest","serverProtocol"],
            "String, protocol of outgoing HTTP requests, defaults to \"http\"."),
        (["proteus","client","rest","serverAddress"],
            "String, address of outgoing HTTP requests, defaults to \"127.0.0.1\"."),
        (["proteus","client","rest","serverPort"],
            "Int16, port of outgoing HTTP requests, defaults to \"80\"."),
        
        (["proteus","runtime","port"],
            "UInt16, REST server port used by FAST application."),
        (["proteus","runtime","address"],
            "String, REST server address used by FAST application, defaults to \"0.0.0.0\"."),
        (["proteus","runtime","profilingPort"],
            "UInt16, REST server port used by FAST sub-processes started during profiling, defaults to 1339."),
        
        (["proteus","runtime","applicationExecutionMode"],
            "one of [Adaptive (default), NonAdaptive, ExhaustiveProfiling, EndPointsProfiling, EmulatorTracing, MachineLearning]."),
        (["proteus","runtime","interactionMode"],
            "one of [Default (default), Scripted]. in Default mode iterations are processed as quickly as possible, in Scripted mode as a result of calls to the /process REST end-point."),

        (["proteus","runtime","executeWithMachineLearning"],
            "one of [true, false (default)], when true, controller models are requested from the machine learning module when the controller detects excessive oscillation." + 
            "NOTE: Requires that the machine learning module is started in a parallel process."),
        (["proteus","runtime","executeWithTestHarness"],
            "one of [true, false (default)], when true, the initialization parameters and intent are obtained through a call to the test harness' /ready REST end-point."),
        (["proteus","runtime","sendStatusToTestHarness"],
            "one of [true, false (default)], when true status messages are posted to the test harness' /status REST end-point after every iteration."),
        (["proteus","runtime","detailedStatusMessages"],
            "one of [true, false (default)].\n" + 
            "By default, status messages will contain the verdict components as well as the current value of each measure.\n" +
            "Setting this flag to \"true\" will add information about: \n" +
            " - knob values (application, system configuration [platform], and scenario)\n" +
            " - architecture\n" +
            " - measure statistics (if these are enabled by the proteus_runtime_outputMeasureStatistics flag)."),
        (["proteus","runtime","suppressStatus"],
            "one of [true, false (default)], when true, this will completely turn off logging of status messages (both to standard output and to the test harness' /status REST end-point)."),
        (["proteus","runtime","minimumSecondsBetweenStatuses"],
            "Double, wait at least this long between successive status message logs."),
        (["proteus","runtime","outputMeasureStatistics"],
            "one of [true, false (default)], when true, current statistics of the measures are included in status messages."),
        (["proteus","runtime","outputMeasurePredictions"],
            "one of [true, false (default)], when true, the measure values associated (through the current model) with the current configuration will be included in status messages."),
        (["proteus","runtime","collectDetailedStatistics"],
            "one of [true, false (default)], when true, the MeasuringDevice will collect statistics for each combination of measure and KnobSettings."),

        (["proteus","architecture","linuxDvfsGovernor"],
            "one of [Performance (default), Userspace], linux DVFS governor."),

        (["proteus","armBigLittle","availableBigCores"],
            "Int, scenario knob, upper bound to the utilizedBigCores platform knob."),
        (["proteus","armBigLittle","availableLittleCores"],
            "Int, scenario knob, upper bound to the utilizedLittleCores platform knob."),
        (["proteus","armBigLittle","maximalBigCoreFrequency"],
            "Int, scenario knob, upper bound to the utilizedBigCoreFrequency platform knob."),
        (["proteus","armBigLittle","maximalLittleCoreFrequency"],
            "Int, scenario knob, upper bound to the utilizedLittleCoreFrequency platform knob."),
        (["proteus","armBigLittle","utilizedBigCores"],
            "one of [0,1,2,3,4]"),
        (["proteus","armBigLittle","utilizedLittleCores"],
            "one of [0,1,2,3,4]"),
        (["proteus","armBigLittle","executionMode"],
            "one of [Default (default), Emulated], when Emulated, time and energy are read from the emulation database."),
        (["proteus","armBigLittle","actuationPolicy"],
            "one of [Actuate, NoActuation], when set to NoActuation, changes to the utilizedCores and utilizedCoreFrequency platform knobs are ignored."),

        (["proteus","xilinxZcu","availableCores"],
            "Int, scenario knob, upper bound to the utilizedCores platform knob."),
        (["proteus","xilinxZcu","availableCoreFrequency"],
            "Int, scenario knob, upper bound to the utilizedCoreFrequency platform knob."),
        (["proteus","xilinxZcu","utilizedCores"],
            "one of [0,1,2,3,4]"),
        (["proteus","xilinxZcu","utilizedCoreFrequency"],
            "one of [400, 600, 1200]"),
        (["proteus","xilinxZcu","executionMode"],
            "one of [Default (default), Emulated], when Emulated, time and energy are read from the emulation database."),
        (["proteus","xilinxZcu","actuationPolicy"],
            "one of [Actuate, NoActuation], when set to NoActuation, changes to the utilizedCores and utilizedCoreFrequency platform knobs are ignored.")

    ]

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

@discardableResult public func intend
(
    _ optimizationScope  : String,
    to optimizationType  : OptimizationType? = nil,
    objective            : (([ String: Double ]) -> Double)? = nil,
    objectiveString      : String? = nil,
    suchThat constraints : [ (measure: String, is: ConstraintType, goal: Double) ]? = nil
) -> Void 
{
    guard let r = runtime else {
        FAST.fatalError("Attempt to set intent '\(optimizationScope)' before runtime is initialized.")
    }

    guard 
        let currentIntentSpec = runtime.intents[optimizationScope],
        let currentCompiledIntentSpec = currentIntentSpec as? Compiler.CompiledIntentSpec
    else {
        FAST.fatalError("No application with name '\(optimizationScope)' registered in the runtime.")
    }

    func deduceObjectiveRepresentations() -> ( (([Double]) -> Double)?, String? ){
        if objective == nil && objectiveString == nil {
            return (currentCompiledIntentSpec.costOrValue, currentCompiledIntentSpec.objectiveFunctionRawString)
        }
        if objective == nil {
            return (nil, objectiveString)
        }
        return (
            { measureValues in
                objective!(
                    Dictionary(
                        Array(zip(currentCompiledIntentSpec.measures,measureValues))
                    )
                )
            },
            objectiveString
        )
    }

    let (nextCostOrValue, nextObjectFunctionRawString) = deduceObjectiveRepresentations()

    runtime.changeIntent(to: Compiler.CompiledIntentSpec(
        name                       : currentCompiledIntentSpec.name,
        knobs                      : currentCompiledIntentSpec.knobs,
        measures                   : currentCompiledIntentSpec.measures,
        constraints                : constraints == nil ? currentCompiledIntentSpec.constraints
                                                        : Dictionary(constraints!.map{
                                                             (measure, relation, goal) in (measure, (goal, relation))
                                                          }), 
        optimizationType           : optimizationType ?? currentCompiledIntentSpec.optimizationType,
        trainingSet                : currentCompiledIntentSpec.trainingSet,
        costOrValue                : nextCostOrValue,
        objectiveFunctionRawString : nextObjectFunctionRawString,
        knobConstraintsRawString   : currentCompiledIntentSpec.knobConstraintsRawString
    ))

}

@discardableResult public func measure(_ name: String, _ value: Double) -> Double {
    return runtime.measure(name, value)
}

extension Knob where T: Equatable {
    
    /** 
     * Returns, for each optimization scope, the set of values that the 
     * controller is allowed to choose from, based on the currently active 
     * model filters, that is, on:
     * 
     *   - The current intent, whose knob ranges may be subsets of those
     *     of the intent that was used to generate the original model used
     *     to start the application. This can be a result of the actual knob
     *     ranges being smaller, of tighter knob constraints, or of both.
     *     
     *   - The currently active knob restrictions, resulting from calls to
     *     the Knob.restrict() method.
     */
    public func range() -> [ String : [T] ] {
        guard let r = runtime else {
            FAST.fatalError("Attempt to get the range of knob '\(self.name)' before the runtime was initialized.")
        } 
        return Dictionary(
            r.models.map{ 
                modelForOptimizationScope in 
                let (optimizationScope, (_,unTrimmedModel)) = modelForOptimizationScope
                guard let activeIntent = r.intents[optimizationScope] else {
                    FAST.fatalError("Attempt to get the active intent for unkonwn optimization scope '\(optimizationScope)'.")
                }
                let trimmedModel = r.trimModelToFilters(unTrimmedModel, activeIntent)
                return (
                    optimizationScope, 
                    trimmedModel.range(ofKnob: self.name)
                )
            }
        )
    }

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
