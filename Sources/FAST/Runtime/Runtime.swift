/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Main File
 *
 *  author: Adam Duracz
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//---------------------------------------

import Foundation
import Dispatch
import LoggerAPI
import CSwiftV

//------ runtime interaction & initialization

// Key prefix for initialization
fileprivate let key = ["proteus","runtime"]

//------ runtime interaction

public class Runtime {
    fileprivate init() {}

    static func newRuntime() -> Runtime {
        let runtime = Runtime()
        runtime.reset()
        return runtime
    }

    // FIXME: Replace by initializer, after making static var:s into instance variables.
    func reset() {
        isSystemMeasuresRegistered = false

        measures                 = [:]
        measuresLock             = NSLock()
        measuringDevices         = [:]

        knobSetters              = [:]
        knobRanges               = [:]
        knobLock                 = NSLock()

        intents                  = [:]
        models                   = [:]
        modelFilters             = [:]
        modelFiltersWereUpdated  = true
        controller               = ConstantController()
        controllerLock           = NSLock()

        architecture             = nil // DefaultArchitecture(runtime: self): this calls registerSystemMeasures, not good!
        application              = nil

        runtimeKnobs             = RuntimeKnobs(key, runtime: self)

        scenarioKnobs            = ScenarioKnobs(key)

        scriptedCounter          = 0

        shouldTerminate          = false

        apiModule                = RuntimeApiModule(runtime: self)

        schedule                 = nil

    }

    // REST server port used by FAST application
    let restServerPort          = initialize(type: UInt16.self, name: "port",          from: key, or: 1338)
    // REST server port used by FAST sub-processes started during profiling
    let profilingRestServerPort = initialize(type: UInt16.self, name: "profilingPort", from: key, or: 1339)
    // REST server address used by FAST application
    let restServerAddress       = initialize(type: String.self, name: "address",       from: key, or: "0.0.0.0")

    // Controls whether or not the machine learning module will be used to update the controller model online.
    let executeWithMachineLearning = initialize(type: Bool.self, name: "executeWithMachineLearning", from: key, or: false)

    // Controls whether or not the test harness is involved in the execution.
    // This includes obtaining initialization parameters are obtained from response to post to brass-th/ready,
    // and posting to brass-th/status after the processing of each input.
    let executeWithTestHarness = initialize(type: Bool.self, name: "executeWithTestHarness", from: key, or: false)

    // When executing with a test harness (proteus_runtime_executeWithTestHarness=true), send a status message
    // after every iteration has completed.
    let sendStatusToTestHarness = initialize(type: Bool.self, name: "sendStatusToTestHarness", from: key, or: false)

    // Controls whether or detailed status messages are output.
    // By default, status messages will contain the verdict components as well as the current value of each measure.
    // Setting this flag to "true" will add information about: 
    //  - knob values (application, system configuration [platform], and scenario)
    //  - architecture
    //  - measure statistics
    let detailedStatusMessages = initialize(type: Bool.self, name: "detailedStatusMessages", from: key, or: false)
    
    // Completely turn off logging of status messages (both to standard output and to the test harness' /status end-point).
    let suppressStatus = initialize(type: Bool.self, name: "suppressStatus", from: key, or: false)

    // Wait at least this long between successive status message logs.
    let minimumSecondsBetweenStatuses = initialize(type: Double.self, name: "minimumSecondsBetweenStatuses", from: key, or: 0.0)

    // When set to true, the MeasuringDevice will collect statistics for each combination of measure and KnobSettings.
    let collectDetailedStatistics = initialize(type: Bool.self, name: "collectDetailedStatistics", from: key, or: false)

    // When true, log messages are not written to the output/error stream until the end of execution, which reduces overhead.
    let logToMemory = initialize(type: Bool.self, name: "logToMemory", from: ["proteus","runtime"], or: false)

    // Names of measures registered by the runtime. 
    // Along with the systemMeasures registered by the architecture, these are reserved measure names.
    let runtimeMeasures = 
        ["windowSize", "iteration", "latency", "energyDelta", "energy", "runningTime", "performance", "powerConsumption", "currentConfiguration"]

    func resetRuntimeMeasures(windowSize: UInt32) {
        self.measure("windowSize", Double(windowSize))
        self.measure("iteration", 0.0)
        self.measure("latency", 0.0) // latency in seconds
        self.measure("energyDelta", 0.0) // energy per iteration
        self.measure("energy", 0.0) // energy since application started or was last reset
        self.measure("runningTime", 0.0) // running time in seconds
        self.measure("performance", 0.0) // seconds per iteration
        self.measure("powerConsumption", 0.0) // rate of energy
        self.measure("currentConfiguration", -1.0)
        let unInitializedRuntimeMeasures = runtimeMeasures.filter{self.getMeasure($0) == nil}
        assert(unInitializedRuntimeMeasures.isEmpty, "Some runtime measures have not been initialized: \(unInitializedRuntimeMeasures).")
    }

    var runtimeAndSystemMeasures: [String] {
        get {
            let systemMeasures = architecture?.systemMeasures ?? []
            return systemMeasures + runtimeMeasures
        }
    }

    // FIXME: set to 0 for now, Emulator should detect app input stream 
    let applicationInputId = 0

    var isSystemMeasuresRegistered = false

    private var measures: [String : Double] = [:]
    private var measuresLock = NSLock()
    var measuringDevices: [String : MeasuringDevice] = [:]

    var knobSetters: [String : (Any) -> Void] = [:]
    var knobLock = NSLock()
    var knobRanges: [String : [Any]] = [:]
    // Used to find the index of the current configuration for use by the controller
    var currentKnobSettings: KnobSettings? = nil

    var intents: [String : IntentSpec] = [:]
    // Map from intent name to a pair (m1,m2) of Models, where 
    // - m1 is the currently active model, and 
    // - m2 is the original, untrimmed model (before trimming w.r.t. intent and modelFilters)
    var models: [String : (Model,Model)] = [:]
    // This dictionary associates a filter name (String), with a function that,
    // given a Configuration, says whether or not it should remain in the model.
    // Used to implement toggling of control for knobs, to implement scenario
    // knobs, and to implement filtering of the model using intents with smaller
    // knob ranges.
    var modelFilters: [String : (Configuration) -> Bool] = [:]
    // Used to ensure that the application is executed for at least one window using
    // the ConstantController before an adaptive controller is initialized, so that
    // the measure estimates for the initial configuration can be provided to the
    // adaptive controller upon initialization.
    // When the model is updated, e.g. when Knob.restrict() is called, the 
    // modelFiltersWereUpdated variable will be set to true, prompting the optimize 
    // loop to switch to a ConstantController for at least one window, to ensure
    // valid measure values are passed to the adaptive controller when it is
    // instantiated with the new model.
    var modelFiltersWereUpdated: Bool = true

    var controller: Controller = ConstantController()
    var controllerLock = NSLock()

    let intentCompiler = Compiler()

    var schedule: Schedule? = nil

    /**
     * Read it from the file system. The intent will be loaded from a file whose
     * name is <APPLICATION_PATH>/<ID>.intent, where <APPLICATION_PATH> is the
     * location of the application and <ID> is the value of the id parameter.
     */
    func readIntentFromFile(_ id: String) -> IntentSpec? {
        if let intentFileContent = readFile(withName: id, ofType: "intent") {
            if let intent = intentCompiler.compileIntentSpec(source: intentFileContent) {
                return intent
            }
            else {
                Log.debug("Unable to compile intent '\(id)'.")
                return nil
            }
        }
        else {
            Log.debug("Unable to load intent '\(id)'.")
            return nil
        }
    }

    func setIntent(_ spec: IntentSpec) {
        intents[spec.name] = spec
        Log.info("Set intent for optimize scope '\(spec.name)' to: \(spec).")
    }

    /**
     * When the model is changed e.g. by a call to the Knob.restrict() or 
     * Knob.control() API, this function will pick a configuration in the 
     * filtered model, instantiate ConstantController based on this 
     * configuration, and assign this as the active controller in the runtime.
     * The Optimize.run() function will let this controller control the system
     * (i.e. keep it in a fixed configuration) for at least one window, before
     * instantiating an adaptive controller. This way, the measure averages that
     * are passed to the adaptive controller to compute its initial schedule
     * will accurately reflect the behavior in the initial configuration.
     *
     * Returns: The knob settings in which the ConstantController will run.
     */
    @discardableResult func registerModel(for intent: IntentSpec, _ model: Model, withInitialKnobSettings initialKnobSettings: KnobSettings? = nil) -> KnobSettings {
        // Trim the model w.r.t. any registered filters.
        let trimmedModel = trimModelToFilters(model, intent)
        models[intent.name] = (trimmedModel, model)
        Log.info("Set model for optimize scope '\(intent.name)'.")
        // Set the active controller to a ConstantController
        // Unless overridden, pick configuration 0 since FASTController assumes the model is sorted by the constraint measure
        let initialSettings = initialKnobSettings ?? trimmedModel.configurations[0].knobSettings
        self.currentKnobSettings = initialSettings
        self.controller = ConstantController(knobSettings: initialSettings)
        self.schedule = self.controller.getSchedule(intent, [String:Double]())
        Log.info("Constant controller initialized, it will run the application in the following, fixed configuration: \(initialSettings).")
        return initialSettings
    }

    func trimModelToFilters(_ model: Model, _ intent: IntentSpec) -> Model {
        // Trim model with respect to the filters that have been registered in the runtime modelFilters array.
        // These include application knob filters, that are used to implement toggling of control with respect
        // to individual knobs using the Knob type's public API.
        var modelTrimLog = [String]()
        let modelTrimmedToFilters = self.modelFilters.reduce(model, {
            (m: Model, descriptionAndFilter: (String, (Configuration) -> Bool)) in 
            let (description, filter) = descriptionAndFilter
            let modelAfterThisFilter = m.trim(toSatisfy: filter, description)
            modelTrimLog.append("Model trimmed to filter '\(description)' (size before: \(m.configurations.count), size after: \(modelAfterThisFilter.configurations.count)).\n")
            return modelAfterThisFilter
        })
        if model.configurations.count < modelTrimmedToFilters.configurations.count {
            for log in modelTrimLog {
                Log.debug(log)
            }
            Log.debug("Model trimmed to registered filters (size before: \(model.configurations.count), size after: \(modelTrimmedToFilters.configurations.count)).")
        }
        else {
            Log.debug("The registered filters did not affect the model.")
        }
        return modelTrimmedToFilters
    }

    /**
     * Read model from the file system. The model will be loaded from two files whose
     * names are <APPLICATION_PATH>/<ID>.knobtable, and
     * <APPLICATION_PATH>/<ID>.measuretable where <APPLICATION_PATH> is the
     * location of the application and <ID> is the value of the id parameter.
     */
    func readModelFromFile(_ id: String, intent: IntentSpec) -> Model? {
        let tableSuffix = "table"
        if let knobCSV = readFile(withName: id, ofType: "knob\(tableSuffix)") {
            if let measureCSV = readFile(withName: id, ofType: "measure\(tableSuffix)") {
                return Model(knobCSV, measureCSV, intent)
            }
            else {
                Log.error("Unable to read measure table \(id).measure\(tableSuffix).")
                return nil
            }
        }
        else {
            Log.error("Unable to read knob table \(id).knob\(tableSuffix).")
            return nil
        }
    }

    /**
     * Assuming the runtime's controller has not yet been initialized, request a new 
     * model from the machine learning module.
     * The purpse of passing the originalModel to the machine learning module is that
     * machine learning can be used to extend the model to include configurations missing
     * in the original model (a.k.a. "filling in the holes" in the orginal model).
     */
    internal func requestInitialModelFromMachineLearning(id: String, activeIntent intent: IntentSpec, originalModel: Model?) -> Model {

        Log.info("Model loaded for optimize scope \(id) in machine learning mode.")
        guard
            let m = originalModel,
            let initJSON = m.toSetupJSON(id: id, intent: intent) else
        {
            FAST.fatalError("Failed in converting initial model to JSON for ML mode.")
        }
        guard let newJSON = MLClient.setup(initJSON) else {
            FAST.fatalError("Failed in getting an updated JSON from ML REST API.")
        }
        guard let newModel = Model(fromMachineLearning: newJSON, intent: intent) else {
            FAST.fatalError("Failed in constructing an updated mode from ML JSON.")
        }
        return newModel
    
    }

    /** 
     * Assuming the runtime's controller has already been initialized, request a new Model from the 
     * machine learning module, and then use it to reinitialize the controller.
     */
    internal func updateModelFromMachineLearning(_ id: String, _ lastWindowConfigIds: [Int], _ lastWindowMeasures: [String: [Double]]) {

        let additionalArguments: [String: Any] = ["lastWindowMeasures": lastWindowMeasures]
        guard let currentIntent = self.intents[id] else {
            FAST.fatalError("Attempt to update from machine learning module without existing intent specification.")
        }
        guard let (_ /* current model will be recomputed */, currentUntrimmedModel) = self.models[id] else {
            FAST.fatalError("Attempt to update from machine learning module without existing controller model.")
        }
        guard let currentUntrimmedModelJSON = currentUntrimmedModel.toUpdateJSON(id: id, lastWindowConfigIds: lastWindowConfigIds, lastWindowMeasures: lastWindowMeasures) else {
            FAST.fatalError("Failed in converting current model to JSON for ML mode.")
        }
        guard let newJSON = MLClient.update(currentUntrimmedModelJSON) else {
            FAST.fatalError("Failed in getting an updated JSON from ML REST API.")
        }
        guard let newModel = Model(fromMachineLearning: newJSON, intent: currentIntent) else {
            FAST.fatalError("Failed in constructing an updated mode from ML JSON.")
        }
        guard let intentPreservingController = self.controller as? IntentPreservingController else {
            FAST.fatalError("Attempt to update model from machine learning module without an active IntentPreservingController.")
        }
        Log.debug("Reinitializing controller with new model from machine learning module.")
        self.reinitializeController(
            currentIntent, 
            replacingCurrentModelWith: newModel
        )

    }

    // The runtime registers the APIs of the platform and application
    var architecture: Architecture? = nil
    var application: Application? = nil

    private var _runtimeKnobs: RuntimeKnobs?
    var runtimeKnobs: RuntimeKnobs {
      set { _runtimeKnobs = newValue }
      get { return _runtimeKnobs! }
    }

    /** Status in the form of a dictionary, for easy conversion to JSON. */
    func statusDictionary() -> [String : Any]? {

        func toArrayOfPairDicts(_ dict: [String : Any]) -> [[String : Any]] {
            return Array(dict).map { (s , a) in ["name" : s, "value" : a] }
        }

        func toArrayOfKnobStateDicts(_ dict: [String : Any]) -> [[String : Any]] {
            return Array(dict).map { 
                (s , valueAndRange) in 
                guard let (value,range) = valueAndRange as? (Any, [Any]) else {
                    FAST.fatalError("Could not cast \(valueAndRange) to a pair of knob value and knob range.")
                }
                return ["name" : s, "value" : value, "range" : range] 
            }
        }

        func unwrapValues(_ dict: [String: Any]) -> [String: Any] {
            return Dictionary(dict.map { (s,a) in (s, (a as! [String: Any])["value"]!) })
        }

        func unwrapKnobState(_ dict: [String: Any]) -> [String: Any] {
            return Dictionary(dict.map { 
                (s,a) in 
                let aDict = a as! [String: Any]
                return (s, (aDict["value"]!, aDict["range"]!)) 
            })
        }

        func extractStatus(from module: TextApiModule) -> [String : Any] {
            return module.getStatus().map{ unwrapValues($0) } ?? [:]
        }

        func extractStatus(of subModule: String, from module: TextApiModule?) -> [String : Any] {
            return (module?.getStatus()?[subModule] as? [String: Any]).map{ unwrapValues($0) } ?? [:]
        }

        func extractKnobStatus(of subModule: String, from module: TextApiModule?) -> [String : Any] {
            return (module?.getStatus()?[subModule] as? [String: Any]).map{ unwrapKnobState($0) } ?? [:]
        }

        if let appName               = application?.name {

            let verdictComponents: [String : Any] =
                Dictionary(measuringDevices.map{
                    (intentName, measuringDevice) in
                    let intentSpec = intents[intentName]!
                    var components = [String : Any]()
                    if 
                        let objectiveFunction           = intentSpec.currentCostOrValue(runtime: self),
                        let objectiveFunctionExpression = intentSpec.objectiveFunctionRawString
                    {
                        components["objectiveFunction"]           = objectiveFunction
                        components["objectiveFunctionExpression"] = objectiveFunctionExpression
                    }
                    components["optimizationType"] = intentSpec.optimizationType == .minimize ? "min" : "max"
                    let measureValues = measuringDevice.values()
                    components["constraints"] = intentSpec.constraints.map {
                        (constraintVariable: String, goalAndType: (Double, ConstraintType)) -> [String : Any] in 
                        let (constraintGoal, constraintType) = goalAndType
                        return [
                            "variable" : constraintVariable,
                            "goal"     : constraintGoal,
                            "value"    : measureValues[constraintVariable]!,
                            "type"     : constraintType.rawValue
                        ]
                    }
                    return ( intentName, components )
                })

            /** measure name -> (statistic name -> statistic)
            * Create a Dictionary of (measureName, statisticsValues) where
            * statisticsValues is a Dictionary of (statisticsName, statisticsValue).
            */
            let measuringDevice = self.measuringDevices[appName]!

            // Extract status from sub-modules (application-, and system configuration knobs)
            let applicationKnobs               = extractKnobStatus(of: "applicationKnobs",         from: application  )
            let systemConfigurationKnobs       = extractKnobStatus(of: "systemConfigurationKnobs", from: architecture )

            var arguments : [String : Any] =
                [ "application"              : appName
                , "measures"                 : toArrayOfPairDicts(getMeasures()) // Current measure values
                , "applicationKnobs"         : toArrayOfKnobStateDicts(applicationKnobs)
                , "systemConfigurationKnobs" : toArrayOfKnobStateDicts(systemConfigurationKnobs)
                , "verdictComponents"        : toArrayOfPairDicts(verdictComponents)
                ]
            
            if detailedStatusMessages {

                // Extract status from other sub-modules (architecture and scenario knobs)

                let archName                       = architecture?.name ?? "NOT CONFIGURED"
                let architecureScenarioKnobsStatus = extractStatus(of: "scenarioKnobs",            from: architecture)
                let scenarioKnobsStatus            = extractStatus(                                from: scenarioKnobs)
                
                var combinedScenarioKnobsStatus: [String: Any] = [:]
                for k in scenarioKnobsStatus.keys {
                    combinedScenarioKnobsStatus[k] = scenarioKnobsStatus[k]
                }
                for k in architecureScenarioKnobsStatus.keys {
                    combinedScenarioKnobsStatus[k] = architecureScenarioKnobsStatus[k]
                }

                // Extract measure statistics
                
                let measureStatistics: [String : [String : Double]] =
                    Dictionary(measuringDevice.stats.map {
                        (measureName: String, stats: Statistics) in
                        (measureName, stats.asJson)
                    })

                // Optionally extract measure predicitons (knob values of current configuration) 
                // and per-configuration measure statistics.

                let applicationExecutionMode = self.runtimeKnobs.applicationExecutionMode.get()
                let isControllerModelAvailable = applicationExecutionMode == .Adaptive || applicationExecutionMode == .MachineLearning

                if isControllerModelAvailable {
                    
                    // The measure values that the controller associates with the current configuration 
                    // through the controller model.
                    // Note: This will only be defined when running in Adaptive or MachineLearning mode.
                    let currentConfiguration = getCurrentConfiguration()!
                    arguments["measurePredictions"] = 
                        zip( currentConfiguration.measureNames
                        , currentConfiguration.measureValues
                        ).map{ [ "name" : $0, "value" : $1 ] }

                    if self.collectDetailedStatistics {

                        // Extract per-KnobSettings statistics
                        // NOTE: This is very expensive! 
                        //       When the time it takes to process an iteration is very low (<10ms),
                        //       enabling proteus_runtime_collectDetailedStatistics will cause energy-derived
                        //       measures such as performance and powerConsumption to be significantly
                        //       affected by the time it takes to output this part of the status message.

                        let measureStatisticsPerKnobSettings: [String: [String : [String: Double]]] =
                            self.collectDetailedStatistics
                                ?   Dictionary(measuringDevice.statsPerKnobSettings.map {
                                        kv in
                                        let measureName = kv.0
                                        let perKnobSettingsStats: [KnobSettings: Statistics] = kv.1
                                        return (measureName, Dictionary(perKnobSettingsStats.map{ (String($0.0.kid), $0.1.asJson) }))
                                    })
                                : [:]

                        arguments["measureStatisticsPerKnobSettings"] = 
                            measureStatisticsPerKnobSettings
                    }
                    
                }
                
                arguments["architecture"            ] = archName
                arguments["scenarioKnobs"           ] = toArrayOfPairDicts(combinedScenarioKnobsStatus)
                arguments["measureStatistics"       ] = measureStatistics // Current measure statistics

            }

            Log.debug("Done extracting statusDictionary.")

            let status : [String : Any] =
                [ "time"      : utcDateString()
                , "arguments" : arguments
                ]

            return status

        }
        else {
            return nil
        }

    }


    func changeInteractionMode(oldMode: InteractionMode, newMode: InteractionMode) -> Void {

        // Change applies only if the value has changed
        if (oldMode != newMode) && (newMode == .Scripted) {
            scriptedCounter = 0
        }
    }

    private var _scenarioKnobs: ScenarioKnobs?
    var scenarioKnobs: ScenarioKnobs {
      set { _scenarioKnobs = newValue }
      get { return _scenarioKnobs! }
    }

    /**
     * When running in the Scripted InteractionMode, (controlled by the environment variable
     * proteus_runtime_interactionMode) instruct the Runtime to process numberOfInputs inputs,
     * and block until it has completed their processing.
     */
    func process(numberOfInputs: UInt64) {

        scriptedCounter += UInt64(numberOfInputs)

        while (runtimeKnobs.interactionMode.get() == .Scripted &&
               scriptedCounter > 0) {}

    }

    // for the scripted mode
    var scriptedCounter: UInt64 = 0

    // shared var to sense quit command over communcation channel
    var shouldTerminate = false

    // decrements the iteration counter when the application is executing in scripted mode
    func decrementScriptedCounter() {

        if (runtimeKnobs.interactionMode.get() == .Scripted) {

            if scriptedCounter > 0 {
                scriptedCounter -= 1
            }

        }

    }

    // blocks until the counter is > 0 if the application is executing in scripted mode
    func waitForRestCallToIncrementScriptedCounter() {


        // keeps track of the counter and blocks the application in scripted mode
        if (runtimeKnobs.interactionMode.get() == .Scripted) {
            
            if scriptedCounter == 0 {
                Log.debug("Waiting for runtime.scriptedCounter to be incremented (e.g. by the REST API's /process end-point.)")
            }

            while (runtimeKnobs.interactionMode.get() == .Scripted &&
                   scriptedCounter == 0 &&
                   !shouldTerminate) {}
        }

    }

    // the instance of the runtime api
    private var _apiModule: RuntimeApiModule?
    public var apiModule: RuntimeApiModule {
      set { _apiModule = newValue }
      get { return _apiModule! }
    }

    // architecture initialization, right now it comes from the application, this needs to be thought through
    func initializeArchitecture(name architectureName: String) {
        switch architectureName {
            case "ArmBigLittle":
                self.architecture = ArmBigLittle(runtime: self)

            case "XilinxZcu":
                self.architecture = XilinxZcu(runtime: self)

            case "Default":
                self.architecture = DefaultArchitecture(runtime: self)

            case "Dummy":
                self.architecture = DummyArchitecture(runtime: self)

            default:
                break
        }

        reregisterSubModules()
    }

    // application initialization
    func registerApplication(application: Application) {

        self.application = application

        reregisterSubModules()
    }

    // application and architecture might be initialized in various orders, this makes sure everything is current
    func reregisterSubModules() -> Void {
        apiModule.subModules = [String : TextApiModule]()
        if let architecture = self.architecture {
            apiModule.addSubModule(newModule: architecture)
        }
        if let application = self.application {
            apiModule.addSubModule(newModule: application)
        }
        apiModule.addSubModule(newModule: self.runtimeKnobs)

        recursivelyFindAndRegisterKnobs(apiModule)
    }

    private func recursivelyFindAndRegisterKnobs(_ module: TextApiModule) {
      if let knob = module as? IKnob {
        knobSetters[knob.name] = knob.setter
      }

      for (_, submodule) in module.subModules {
        recursivelyFindAndRegisterKnobs(submodule)
      }
    }


    /** Intialize intent preserving controller with the given model, intent, and window. */
    func initializeController(_ model: Model, _ intent: IntentSpec, _ window: UInt32 = 20) {
        
        setIntent(intent)
        registerModel(for: intent, model)
        let (modelTrimmedToBothIntentAndFilters, _) = self.models[intent.name]!
        
        Log.debug("Will now initialize controller for intent with \(intent.constraints.count) constraints.")
        
        synchronized(controllerLock) {
            switch intent.constraints.count {
            case 1:    
                if let c = IntentPreservingController(modelTrimmedToBothIntentAndFilters, intent, self, window) {
                    controller = c
                    Log.info("IntentPreservingController initialized.")
                }
                else {
                    FAST.fatalError("IntentPreservingController failed to initialize.")
                }

            case 2...:    
                if let c = MulticonstrainedIntentPreservingController(modelTrimmedToBothIntentAndFilters, intent, window) {
                    controller = c
                    Log.info("MulticonstrainedIntentPreservingController initialized.")
                }
                else {
                    FAST.fatalError("MulticonstrainedIntentPreservingController failed to initialize.")
                }

            case 0:
                if let c = UnconstrainedIntentPreservingController(modelTrimmedToBothIntentAndFilters, intent, window) {
                    controller = c
                    Log.info("UnconstrainedIntentPreservingController initialized.")
                }
                else {
                    FAST.fatalError("UnconstrainedIntentPreservingController failed to initialize.")
                }

            default:
                FAST.fatalError("Intent doesn't havae any constraint initialized.")
            }
        }
    }

    /** Reintialize intent preserving controller with the intent, keeping the previous model and window */
    public func reinitializeController(_ spec: IntentSpec, replacingCurrentModelWith newModel: Model? = nil) {
        if 
            let (_ /* currentModel will be recomputed */, untrimmedModel) = self.models[spec.name]
        {
            // Use the passed model if available, otherwise use the model of the active controller
            var model = newModel ?? untrimmedModel
            initializeController(model, spec, controller.window)   
        } 
        else if let constantController = self.controller as? ConstantController {
            setIntent(spec)
        } else {
            FAST.fatalError("Attempt to reinitialize controller based on a controller (of type \(type(of: self.controller))) with an undefined model.")
        }
    }

    /** Update the value of name in the global measure store and return that value */
    @discardableResult func measure(_ name: String, _ value: Double) -> Double {
        synchronized(measuresLock) {
            measures[name] = value
        }
        Log.debug("Registered value \(value) for measure \(name).")
        return value
    }

    /** Get the current value of a measure */
    func getMeasure(_ name: String) -> Double? {
        return synchronized(measuresLock) {
            return measures[name]
        }
    }

    /** Get the current values of all measures */
    func getMeasures() -> [String : Double] {
        return synchronized(measuresLock) {
            return measures
        }
    }

    /** Get the current Configuration */
    func getCurrentConfiguration() -> Configuration? {
        let appName = application!.name
        switch self.runtimeKnobs.applicationExecutionMode.get() {
            // Get current configuration from model
            case .Adaptive, .MachineLearning:
                if 
                    let currentKnobSettingsId = getMeasure("currentConfiguration"), // kid of the currently active KnobSettings
                    let (currentModel, _ /* ignore untrimmed model */) = models[appName] // Will be defined when running in Adaptive/MachineLearning mode
                {
                    if let currentConfiguration = currentModel.configurations.first(where: { $0.knobSettings.kid == Int(currentKnobSettingsId) }) {
                        return currentConfiguration
                    }
                    else {
                        FAST.fatalError("Configuration with id \(currentKnobSettingsId) (the current configuration id) not found in current model, which contains configurations with ids: '\(currentModel.configurations.map{$0.knobSettings.kid})'. Intent specification may be inconsistent with the model.")
                    }
                }
                else {
                    FAST.fatalError("Can not get current configuration, no model defined for '\(appName)'.")
                }
            // Current configuration not defined in model
            default:
                return nil 
        }
    }

    /** Update the value of name in the global measure store and return that value */
    func setKnob(_ name: String, to value: Any) {
        if let setKnobTo = knobSetters[name] {
            setKnobTo(value)
        }
        else {
            FAST.fatalError("Tried to assign \(value) to an unknown knob called \(name).")
        }
    }

    /** Set scenario knobs according to perturbation */
    func setScenarioKnobs(accordingTo perturbation: Perturbation) {

        var newSettings: [String : [String : Any]] = [
            "missionLength":      ["missionLength":      perturbation.missionLength]
        ]
        self.scenarioKnobs.setStatus(newSettings: newSettings)
        self.setKnob("availableCores",         to: perturbation.availableCores)
        self.setKnob("availableCoreFrequency", to: perturbation.availableCoreFrequency)

        // Set model filters and update knob ranges for the system configuraiton knobs accordingly

        if 
            let (utilizedCoresKnobRange, _): ([Any], Any) = perturbation.missionIntent.knobs["utilizedCores"],
            let range = utilizedCoresKnobRange as? [Int]
        {
            self.knobRanges["utilizedCores"] = range.filter{ $0 <= Int(perturbation.availableCores) }
            self.modelFiltersWereUpdated = true
        }

        if 
            let (utilizedCoreFrequencyKnobRange, _) = perturbation.missionIntent.knobs["utilizedCoreFrequency"],
            let range = utilizedCoreFrequencyKnobRange as? [Int]
        {
            self.knobRanges["utilizedCoreFrequency"] = range.filter{ $0 <= Int(perturbation.availableCoreFrequency) }
            self.modelFiltersWereUpdated = true
        }

        if self.modelFiltersWereUpdated {
            setIntentModelFilter(perturbation.missionIntent)
        }

    }

}
