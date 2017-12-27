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

public class Runtime {

    private init() {}
    
    // FIXME: Replace by initializer, after making static var:s into instance variables.
    static func reset() {
        Runtime.measures                 = [:]
        Runtime.measuresLock             = NSLock()
        
        Runtime.knobSetters              = [:]
        Runtime.knobSettersLock          = NSLock()
        
        Runtime.intents                  = [:]
        Runtime.models                   = [:]
        Runtime.controller               = ConstantController()
        Runtime.controllerLock           = NSLock()
        
        Runtime.architecture             = DefaultArchitecture()
        Runtime.application              = nil

        Runtime.communicationChannel     = nil

        Runtime.runtimeKnobs             = RuntimeKnobs(key)

        Runtime.scenarioKnobs            = ScenarioKnobs(key)

        Runtime.scriptedCounter          = 0

        Runtime.shouldTerminate          = false

        Runtime.apiModule                = RuntimeApiModule()
    }

    static let restServerPort    = initialize(type: UInt16.self, name: "port",    from: key, or: 1338)
    static let restServerAddress = initialize(type: String.self, name: "address", from: key, or: "0.0.0.0")
    // Controls whether or not the test harness is involved in the execution.
    // This includes obtaining initialization parameters are obtained from response to post to brass-th/ready,
    // and posting to brass-th/status after the processing of each input.
    static let executeWithTestHarness = initialize(type: Bool.self, name: "executeWithTestHarness", from: key, or: false)

    private static var measures: [String : Double] = [:]
    private static var measuresLock = NSLock()
    static var measuringDevices: [String : MeasuringDevice] = [:]

    static var knobSetters: [String : (Any) -> Void] = [:]
    static var knobSettersLock = NSLock()

    static var intents: [String : IntentSpec] = [:]
    static var models: [String : Model] = [:]
    static var controller: Controller = ConstantController()
    static var controllerLock = NSLock()

    static let intentCompiler = Compiler()

    /** 
     * Read it from the file system. The intent will be loaded from a file whose
     * name is <APPLICATION_PATH>/<ID>.intent, where <APPLICATION_PATH> is the 
     * location of the application and <ID> is the value of the id parameter. 
     */
    public static func readIntentFromFile(_ id: String) -> IntentSpec? {
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

    static func setIntent(_ spec: IntentSpec) {
        intents[spec.name] = spec
        Log.info("Set intent for optimize scope '\(spec.name)' to: \(spec).")
    }

    static func setModel(name: String, _ model: Model) {
        models[name] = model
        Log.info("Set model for optimize scope '\(name)'.")
    }

    /** 
     * Read model from the file system. The model will be loaded from two files whose
     * names are <APPLICATION_PATH>/<ID>.knobtable, and 
     * <APPLICATION_PATH>/<ID>.measuretable where <APPLICATION_PATH> is the 
     * location of the application and <ID> is the value of the id parameter. 
     */
    public static func readModelFromFile(_ id: String, _ initialConfigurationIndex: Int = 0) -> Model? {
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
    static var architecture: Architecture? = DefaultArchitecture()
    static var application: Application? = nil

    // The runtime manages communcations e.g. TCP
    static var communicationChannel: CommunicationServer? = nil

    static func shutdown() -> Void {
        // TODO implement global exit, now only the server thread quits
        exit(0)
    }

    static public func establishCommuncationChannel(port: Int = 1337) {

        Runtime.communicationChannel = TcpSocketServer(port: port)
        Runtime.communicationChannel!.run(MessageHandler())
    }



    static var runtimeKnobs: RuntimeKnobs = RuntimeKnobs(key)

    /** Status in the form of a dictionary, for easy conversion to JSON. */
    static func statusDictionary() -> [String : Any]? {
        
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

        if let application               = Runtime.application?.name {

            let applicationKnobs         = extractStatus(of: "applicationKnobs",         from: Runtime.application  )
            let architecture             = Runtime.architecture?.name ?? "NOT CONFIGURED"
            let systemConfigurationKnobs = extractStatus(of: "systemConfigurationKnobs", from: Runtime.architecture ) 
            let scenarioKnobs            = extractStatus(                                from: Runtime.scenarioKnobs)
            
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
                [ "application"              : application
                , "applicationKnobs"         : toArrayOfPairDicts(applicationKnobs)
                , "architecture"             : architecture
                , "systemConfigurationKnobs" : toArrayOfPairDicts(systemConfigurationKnobs)
                , "scenarioKnobs"            : toArrayOfPairDicts(scenarioKnobs)
                , "measures"                 : toArrayOfPairDicts(Runtime.getMeasures())
                , "verdictComponents"        : toArrayOfPairDicts(verdictComponents)
                ] 

            // The measure values that the controller associates with the current configuration
            if let currentKnobSettingsId = Runtime.getMeasure("currentConfiguration"), // kid of the currently active KnobSettings
               let currentConfiguration = models[application]!.configurations.first(where: { $0.knobSettings.kid == Int(currentKnobSettingsId) }) {
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


    static func changeInteractionMode(oldMode: InteractionMode, newMode: InteractionMode) -> Void {

        // Change applies only if the value has changed
        if (oldMode != newMode) && (newMode == InteractionMode.Scripted) {
            Runtime.scriptedCounter = 0
        }
    }

    static var scenarioKnobs: ScenarioKnobs = ScenarioKnobs(key)

    /**
     * When running in the Scripted InteractionMode, (controlled by the environment variable
     * proteus_runtime_interactionMode) instruct the Runtime to process numberOfInputs inputs, 
     * and block until it has completed their processing.
     */
    static func process(numberOfInputs: UInt64) {

        Runtime.scriptedCounter += UInt64(numberOfInputs)

        while (Runtime.runtimeKnobs.interactionMode.get() == InteractionMode.Scripted && 
               Runtime.scriptedCounter > 0) {}

    }

    // for the scripted mode
    static var scriptedCounter: UInt64 = 0

    // shared var to sense quit command over communcation channel
    static var shouldTerminate = false

    // generic function to handle the event that an input has been processed in an optimize loop
    static func reportProgress() {

        // keeps track of the counter and blocks the application in scripted mode
        if (Runtime.runtimeKnobs.interactionMode.get() == InteractionMode.Scripted) {

            if Runtime.scriptedCounter > 0 {
                Runtime.scriptedCounter -= 1
            }

            while (Runtime.runtimeKnobs.interactionMode.get() == InteractionMode.Scripted && 
                   Runtime.scriptedCounter == 0 &&
                   !Runtime.shouldTerminate) {}
        }

        // FIXME PATs cannot be used here, i.e. cant write as? ScenarioKnobEnrichedArchitecture in Swift 3.1.1 so all guys are listed
        if let currentArchitecture = Runtime.architecture as? ArmBigLittle {
            currentArchitecture.enforceResourceUsageAndConsistency()
        }
        if let currentArchitecture = Runtime.architecture as? XilinxZcu {
            currentArchitecture.enforceResourceUsageAndConsistency()
        }

        // actuate system configuration on the hardware
        if let currentArchitecture = Runtime.architecture as? RealArchitecture {
            if currentArchitecture.actuationPolicy.get() == ActuationPolicy.Actuate {
                currentArchitecture.actuate()
            }
        }
    }

    // the instance of the runtime api
    public static var apiModule = RuntimeApiModule()

    // architecture initialization, right now it comes from the application, this needs to be thought through
    public static func initializeArchitecture(name architectureName: String) {
        switch architectureName {
            case "ArmBigLittle": 
                self.architecture = ArmBigLittle()

            case "XilinxZcu":
                self.architecture = XilinxZcu()

            case "Default":
                self.architecture = DefaultArchitecture()

            case "Dummy":
                self.architecture = DummyArchitecture()

            default:
                break
        }

        reregisterSubModules()
    }

    // application initialization
    public static func registerApplication(application: Application) {

        self.application = application

        reregisterSubModules()
    }

    // application and architecture might be initialized in various orders, this makes sure everything is current
    static func reregisterSubModules() -> Void {
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
    public static func initializeController(_ model: Model, _ intent: IntentSpec, _ window: UInt32 = 20) {
        synchronized(controllerLock) {
            if let c = IntentPreservingController(model, intent, window) {
                setIntent(intent)
                setModel(name: intent.name, model)
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
    public static func reinitializeController(_ spec: IntentSpec) {
        if let model = Runtime.controller.model {
            // FIXME Check that the model and updated intent are consistent (that measure and knob sets coincide)
            initializeController(model, spec, Runtime.controller.window)
        }
        else {
            Log.error("Attempt to reinitialize controller based on a controller with an undefined model.")
            fatalError()
        }
    }

    /** Update the value of name in the global measure store and return that value */
    @discardableResult public static func measure(_ name: String, _ value: Double) -> Double {
        synchronized(measuresLock) {
            measures[name] = value
        }
        Log.debug("Registered value \(value) for measure \(name).")
        return value
    }

    /** Get the current value of a measure */
    static func getMeasure(_ name: String) -> Double? {
        return measures[name]
    }

    /** Get the current values of all measures */
    static func getMeasures() -> [String : Double] {
        return measures
    }

    /** Update the value of name in the global measure store and return that value */
    static func setKnob(_ name: String, to value: Any) {
        if let setKnobTo = knobSetters[name] {
            setKnobTo(value)
        }
        else {
            fatalError("Tried to assign \(value) to an unknown knob called \(name).")
        }
    }

}
