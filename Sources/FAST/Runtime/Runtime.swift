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
        knobSettersLock          = NSLock()

        intents                  = [:]
        models                   = [:]
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

    // Controls whether or not the test harness is involved in the execution.
    // This includes obtaining initialization parameters are obtained from response to post to brass-th/ready,
    // and posting to brass-th/status after the processing of each input.
    let executeWithTestHarness = initialize(type: Bool.self, name: "executeWithTestHarness", from: key, or: false)

    // Names of measures registered by the runtime. 
    // Along with the systemMeasures registered by the architecture, these are reserved measure names.
    let runtimeMeasures = 
        ["iteration","time","systemEnergy", "runningTime", "energy", "energyLimit", "energyRemaining", "energyDelta", "latency", "performance", "powerConsumption", "windowSize", "currentConfiguration"]

    func resetRuntimeMeasures(windowSize: UInt32) {
        self.measure("windowSize", Double(windowSize))
        self.measure("iteration", 0.0)
        self.measure("time", 0.0) // system time (possibly emulated)
        self.measure("systemEnergy", 0.0) // energy since system started in microjoules (possibly emulated)
        self.measure("latency", 0.0) // latency in seconds
        self.measure("energyDelta", 0.0) // energy per iteration
        self.measure("energy", 0.0) // energy since application started or was last reset
        self.measure("energyLimit", Double(self.energyLimit ?? 0)) // energyDelta of most energy-inefficient configuration times initial mission length 
        self.measure("energyRemaining", Double(self.energyLimit ?? 0)) // runtime.energyLimit - energy 
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
    var knobSettersLock = NSLock()

    var intents: [String : IntentSpec] = [:]
    var models: [String : Model] = [:]

    var controller: Controller = ConstantController()
    var controllerLock = NSLock()

    let intentCompiler = Compiler()

    var schedule: Schedule? = nil

    // The amount of energy that the system is provisioned with at the start of a mission, 
    // which is assumed to be enough to operate in the configuration with the highest 
    // energyDelta for the entire initial missionLength.
    // NOTE: Is only nil until it is initialized during the computation of the initial schedule
    //       in Optimize.setUpControllerAndComputeInitialScheduleAndConfigurationAndEnergyLimit, 
    //       and should be safe to unwrap at any time during Adaptve executions.
    var energyLimit: UInt64? = nil

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

    func setModel(name: String, _ model: Model) {
        models[name] = model
        Log.info("Set model for optimize scope '\(name)'.")
    }

    /**
     * Read model from the file system. The model will be loaded from two files whose
     * names are <APPLICATION_PATH>/<ID>.knobtable, and
     * <APPLICATION_PATH>/<ID>.measuretable where <APPLICATION_PATH> is the
     * location of the application and <ID> is the value of the id parameter.
     */
    func readModelFromFile(_ id: String, _ initialConfigurationIndex: Int = 0) -> Model? {
        if let knobCSV = readFile(withName: id, ofType: "knobtable") {
            if let measureCSV = readFile(withName: id, ofType: "measuretable") {
                return Model(knobCSV, measureCSV, initialConfigurationIndex)
            }
            else {
                Log.error("Unable to read measure table \(id).measuretable.")
                return nil
            }
        }
        else {
            Log.error("Unable to read knob table \(id).knobtable.")
            return nil
        }
    }

//------------------- very new stuff

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

        func unwrapValues(_ dict: [String: Any]) -> [String: Any] {
            return Dictionary(dict.map { (s,a) in (s, (a as! [String: Any])["value"]!) })
        }

        func extractStatus(from module: TextApiModule) -> [String : Any] {
            return module.getStatus().map{ unwrapValues($0) } ?? [:]
        }

        func extractStatus(of subModule: String, from module: TextApiModule?) -> [String : Any] {
            return (module?.getStatus()?[subModule] as? [String: Any]).map{ unwrapValues($0) } ?? [:]
        }

        if let appName               = application?.name {

            let applicationKnobs               = extractStatus(of: "applicationKnobs",         from: application  )
            let archName                       = architecture?.name ?? "NOT CONFIGURED"
            let systemConfigurationKnobs       = extractStatus(of: "systemConfigurationKnobs", from: architecture )
            let architecureScenarioKnobsStatus = extractStatus(of: "scenarioKnobs",            from: architecture)
            let scenarioKnobsStatus            = extractStatus(                                from: scenarioKnobs)

            var combinedScenarioKnobsStatus: [String: Any] = [:]
            for k in scenarioKnobsStatus.keys {
                combinedScenarioKnobsStatus[k] = scenarioKnobsStatus[k]
            }
            for k in architecureScenarioKnobsStatus.keys {
                combinedScenarioKnobsStatus[k] = architecureScenarioKnobsStatus[k]
            }

            let verdictComponents: [String : Any] =
                Dictionary(measuringDevices.map{
                    (intentName, measuringDevice) in
                    let intentSpec = intents[intentName]!
                    let windowAverages = measuringDevice.windowAverages()
                    let constraintVariableValue = windowAverages[intentSpec.constraintName]!
                    var components =
                        [ "constraintVariableValue" : constraintVariableValue as Any ]
                    if 
                        let objectiveFunction           = intentSpec.currentCostOrValue(runtime: self),
                        let objectiveFunctionExpression = intentSpec.objectiveFunctionRawString
                    {
                        components["objectiveFunction"]           = objectiveFunction
                        components["objectiveFunctionExpression"] = objectiveFunctionExpression
                    }
                    components["constraintGoal"]   = intentSpec.constraint
                    components["constraintName"]   = intentSpec.constraintName
                    components["optimizationType"] = intentSpec.optimizationType == .minimize ? "min" : "max"
                    return ( intentName, components.map { (s,v) in ["name" : s, "value" : v] } )
                })

            /** measure name -> (statistic name -> statistic)
            * Create a Dictionary of (measureName, statisticsValues) where
            * statisticsValues is a Dictionary of (statisticsName, statisticsValue).
            */
            let measureStatistics: [String : [String : Double]] =
                Dictionary(self.measuringDevices[appName]!.stats.map {
                    (measureName: String, stats: Statistics) in
                    (measureName, stats.asJson)
                })

            var arguments : [String : Any] =
                [ "application"              : appName
                , "applicationKnobs"         : toArrayOfPairDicts(applicationKnobs)
                , "architecture"             : archName
                , "systemConfigurationKnobs" : toArrayOfPairDicts(systemConfigurationKnobs)
                , "scenarioKnobs"            : toArrayOfPairDicts(combinedScenarioKnobsStatus)
                , "measures"                 : toArrayOfPairDicts(getMeasures()) // Current measure values
                , "measureStatistics"        : measureStatistics                 // Current measure statistics
                , "verdictComponents"        : toArrayOfPairDicts(verdictComponents)
                ]

            // The measure values that the controller associates with the current configuration
            if let currentKnobSettingsId = getMeasure("currentConfiguration"), // kid of the currently active KnobSettings
               let currentModel = models[appName], // Will be undefined when running in NonAdaptive mode, omitting this from the Status message
               let currentConfiguration = currentModel.configurations.first(where: { $0.knobSettings.kid == Int(currentKnobSettingsId) }) {
                arguments["measurePredictions"] = zip( currentConfiguration.measureNames
                                                     , currentConfiguration.measureValues
                                                    ).map{ [ "name" : $0, "value" : $1 ] }
            }

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
//------------------- end of very new stuff

    /** Intialize intent preserving controller with the given model, intent, missionLength and window. */
    func initializeController(_ model: Model, _ intent: IntentSpec, _ window: UInt32 = 20, _ missionLength: UInt64, _ enforceEnergyLimit: Bool, _ sceneImportance: Double? = nil) {
        // Trim model with respect to the intent, to force the controller to choose only those
        // configurations that the user has specified there.
        let trimmedModel = model.trim(to: intent)
        synchronized(controllerLock) {
            if let c = IntentPreservingController(trimmedModel, intent, window, missionLength, self.energyLimit, enforceEnergyLimit, sceneImportance) {
                setIntent(intent)
                setModel(name: intent.name, trimmedModel)
                controller = c
                Log.info("Controller initialized.")
            }
            else {
                Log.error("Controller failed to initialize.")
                fatalError()
            }
        }
    }

    /** Intialize intent preserving controller with the intent, keeping the previous model and window */
    public func reinitializeController(_ spec: IntentSpec, _ missionLength: UInt64?, _ enforceEnergyLimit: Bool?, _ sceneImportance: Double? = nil) {
        if let intentPreservingController = self.controller as? IntentPreservingController {
            initializeController(intentPreservingController.model!, spec, controller.window, 
                missionLength      ?? intentPreservingController.missionLength,
                enforceEnergyLimit ?? intentPreservingController.enforceEnergyLimit, 
                sceneImportance    ?? intentPreservingController.sceneImportance)
        } 
        else if let constantController = self.controller as? ConstantController {
            setIntent(spec)
        } else {
            Log.error("Attempt to reinitialize controller based on a controller with an undefined model.")
            fatalError()
        }
    }

    public func changeIntent(_ spec: IntentSpec, _ missionLength: UInt64? = nil, _ enforceEnergyLimit: Bool? = nil, _ sceneImportance: Double? = nil) {
      guard let intentPreservingController = controller as? IntentPreservingController else {
        Log.error("Active controller type '\(type(of: controller))' does not support change of intent.")
        return
      }
      if spec.isEverythingExceptConstraitValueIdentical(to: intents[spec.name]) {
        // FIXME Also check that missionLength didnt change
        Log.verbose("Knob or measure sets of the new intent are identical to those of the previous intent. Setting the constraint goal of the existing controller to '\(spec.constraint)'.")
        intentPreservingController.fastController.setConstraint(spec.constraint)
        setIntent(spec)
      }
      else {
        Log.verbose("Reinitializing the controller for `\(spec.name)`.")
        reinitializeController(spec, 
            missionLength      ?? intentPreservingController.missionLength, 
            enforceEnergyLimit ?? intentPreservingController.enforceEnergyLimit, 
            sceneImportance    ?? intentPreservingController.sceneImportance)
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

    /** Update the value of name in the global measure store and return that value */
    func setKnob(_ name: String, to value: Any) {
        if let setKnobTo = knobSetters[name] {
            setKnobTo(value)
        }
        else {
            fatalError("Tried to assign \(value) to an unknown knob called \(name).")
        }
    }

    /** Set scenario knobs according to perturbation */
    func setScenarioKnobs(accordingTo perturbation: Perturbation) {
        var newSettings: [String : [String : Any]] = [
            "missionLength":      ["missionLength":      perturbation.missionLength],
            "enforceEnergyLimit": ["enforceEnergyLimit": perturbation.enforceEnergyLimit], 
        ]
        if let sceneImportance = perturbation.sceneImportance {
            newSettings["sceneImportance"] = ["sceneImportance": sceneImportance]
        }
        self.scenarioKnobs.setStatus(newSettings: newSettings)
        self.setKnob("availableCores",         to: perturbation.availableCores)
        self.setKnob("availableCoreFrequency", to: perturbation.availableCoreFrequency)
    }

}
