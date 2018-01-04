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
import Venice
import HeliumLogger
import LoggerAPI
import CSwiftV

//------ runtime interaction & initialization

// Key prefix for initialization
fileprivate let key = ["proteus","runtime"]

//------ runtime interaction

public let Runtime = __Runtime()
@discardableResult public func measure(_ name: String, _ value: Double) -> Double {
    return Runtime.measure(name, value)
}
public class __Runtime {

    fileprivate init() {}

    // FIXME: Replace by initializer, after making static var:s into instance variables.
    func reset() {
        measures                 = [:]
        measuresLock             = NSLock()
        measuringDevices         = [:]

        knobSetters              = [:]
        knobSettersLock          = NSLock()

        intents                  = [:]
        models                   = [:]
        controller               = ConstantController()
        controllerLock           = NSLock()

        architecture             = DefaultArchitecture(runtime: self)
        application              = nil

        communicationChannel     = nil

        runtimeKnobs             = RuntimeKnobs(key)

        scenarioKnobs            = ScenarioKnobs(key)

        scriptedCounter          = 0

        shouldTerminate          = false

        apiModule                = RuntimeApiModule(runtime: self)
    }

    let restServerPort    = initialize(type: UInt16.self, name: "port",    from: key, or: 1338)
    let restServerAddress = initialize(type: String.self, name: "address", from: key, or: "0.0.0.0")
    // Controls whether or not the test harness is involved in the execution.
    // This includes obtaining initialization parameters are obtained from response to post to brass-th/ready,
    // and posting to brass-th/status after the processing of each input.
    let executeWithTestHarness = initialize(type: Bool.self, name: "executeWithTestHarness", from: key, or: false)

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

    /**
     * Read it from the file system. The intent will be loaded from a file whose
     * name is <APPLICATION_PATH>/<ID>.intent, where <APPLICATION_PATH> is the
     * location of the application and <ID> is the value of the id parameter.
     */
    public func readIntentFromFile(_ id: String) -> IntentSpec? {
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
    public func readModelFromFile(_ id: String, _ initialConfigurationIndex: Int = 0) -> Model? {
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

    // The runtime manages communcations e.g. TCP
    var communicationChannel: CommunicationServer? = nil

    func shutdown() -> Void {
        // TODO implement global exit, now only the server thread quits
        exit(0)
    }

    public func establishCommuncationChannel(port: Int = 1337) {

        communicationChannel = TcpSocketServer(port: port, runtime: self)
        communicationChannel!.run(MessageHandler())
    }

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

            let applicationKnobs         = extractStatus(of: "applicationKnobs",         from: application  )
            let archName                 = architecture?.name ?? "NOT CONFIGURED"
            let systemConfigurationKnobs = extractStatus(of: "systemConfigurationKnobs", from: architecture )
            let scenarioKnobsStatus      = extractStatus(                                from: scenarioKnobs)

            let verdictComponents: [String : Any] =
                Dictionary(measuringDevices.map{
                    (intentName, measuringDevice) in
                    let intentSpec = intents[intentName]!
                    let windowAverages = measuringDevice.windowAverages()
                    let constraintVariableValue = windowAverages[intentSpec.constraintName]!
                    var components =
                        [ "constraintVariableValue" : constraintVariableValue ]
                    if let objectiveFunction = intentSpec.currentCostOrValue() {
                        components["objectiveFunction"] = objectiveFunction
                    }
                    return ( intentName, toArrayOfPairDicts(components) )
                })

            var arguments : [String : Any] =
                [ "application"              : appName
                , "applicationKnobs"         : toArrayOfPairDicts(applicationKnobs)
                , "architecture"             : archName
                , "systemConfigurationKnobs" : toArrayOfPairDicts(systemConfigurationKnobs)
                , "scenarioKnobs"            : toArrayOfPairDicts(scenarioKnobsStatus)
                , "measures"                 : toArrayOfPairDicts(getMeasures())
                , "verdictComponents"        : toArrayOfPairDicts(verdictComponents)
                ]

            // The measure values that the controller associates with the current configuration
            if let currentKnobSettingsId = getMeasure("currentConfiguration"), // kid of the currently active KnobSettings
               let currentConfiguration = models[appName]!.configurations.first(where: { $0.knobSettings.kid == Int(currentKnobSettingsId) }) {
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

    // generic function to handle the event that an input has been processed in an optimize loop
    func reportProgress() {

        // keeps track of the counter and blocks the application in scripted mode
        if (runtimeKnobs.interactionMode.get() == .Scripted) {

            if scriptedCounter > 0 {
                scriptedCounter -= 1
            }

            while (runtimeKnobs.interactionMode.get() == .Scripted &&
                   scriptedCounter == 0 &&
                   !shouldTerminate) {}
        }

        // FIXME PATs cannot be used here, i.e. cant write as? ScenarioKnobEnrichedArchitecture in Swift 3.1.1 so all guys are listed
        if let currentArchitecture = architecture as? ArmBigLittle {
            currentArchitecture.enforceResourceUsageAndConsistency()
        }
        if let currentArchitecture = architecture as? XilinxZcu {
            currentArchitecture.enforceResourceUsageAndConsistency()
        }

        // actuate system configuration on the hardware
        if let currentArchitecture = architecture as? RealArchitecture {
            if currentArchitecture.actuationPolicy.get() == .Actuate {
                currentArchitecture.actuate()
            }
        }
    }

    // the instance of the runtime api
    private var _apiModule: RuntimeApiModule?
    public var apiModule: RuntimeApiModule {
      set { _apiModule = newValue }
      get { return _apiModule! }
    }

    // architecture initialization, right now it comes from the application, this needs to be thought through
    public func initializeArchitecture(name architectureName: String) {
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
    public func registerApplication(application: Application) {

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
    }
//------------------- end of very new stuff

    /** Intialize intent preserving controller with the given model, intent and window. */
    public func initializeController(_ model: Model, _ intent: IntentSpec, _ window: UInt32 = 20) {
        synchronized(controllerLock) {
            if let c = IntentPreservingController(model, intent, window) {
                setIntent(intent)
                setModel(name: intent.name, model)
                // controller_ = c
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
    public func reinitializeController(_ spec: IntentSpec) {
        if let model = controller.model {
            // FIXME Check that the model and updated intent are consistent (that measure and knob sets coincide)
            initializeController(model, spec, controller.window)
        }
        else {
            Log.error("Attempt to reinitialize controller based on a controller with an undefined model.")
            fatalError()
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
        return measures[name]
    }

    /** Get the current values of all measures */
    func getMeasures() -> [String : Double] {
        return measures
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

}
