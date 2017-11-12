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
import Nifty

//---------------------------------------

///////////////////
// Runtime State //
///////////////////

/* Wrapper for a value that can be read freely, but can only be changed by the runtime. */
public class Knob<T> {

    public typealias Action = (T, T) -> Void

    var preSetter:  Action
    var postSetter: Action

    // TODO check if these are necessary
    func overridePreSetter(newPreSetter: @escaping Action) -> Void {
        self.preSetter = newPreSetter
    }

    func overridePostSetter(newPostSetter: @escaping Action) -> Void {
        self.postSetter = newPostSetter
    }

    public let name:  String
    var value: T

    public init(_ name: String, _ value: T, _ preSetter: @escaping Action = {_,_ in }, _ postSetter: @escaping Action = {_,_ in }) {

        self.name  = name
        self.value = value
        self.preSetter = preSetter
        self.postSetter = postSetter
        
        Runtime.knobSetters[name] = self.setter
    }

    public func get() -> T {
        return self.value
    }

    internal func set(_ newValue: T, setters: Bool = true) {

        if setters {
            // for the postSetter
            let oldValue = self.value

            self.preSetter(oldValue, newValue)
            self.value = newValue
            self.postSetter(oldValue, newValue)

        } else {
            
            self.value = newValue
        }
    }

    internal func setter(_ newValue: Any) -> Void {

        switch newValue {

            case let castedValue as T:
                self.set(castedValue)

            default:
                fatalError("Tried to assign \(newValue) to a knob of type \(T.self).")
        }
    }
}

//------ runtime interaction & initialization

// Key prefix for initialization
fileprivate let key = ["proteus","runtime"]

enum InteractionMode: String {
    case Default
    case Scripted
}

enum ApplicationExecutionMode {
    // Run application with adaptation.
    case Adaptive
    // Run application without adaptation.
    case NonAdaptive
    // Run application, without adaptation, once for every configuration in the intent specification.
    case ExhaustiveProfiling
    // Run application, without adaptation, for a percentage of the configurations in the intent 
    // specification. The default is to profile all (100%) of the configurations. When only part
    // of the configurations are profiled, the extremeValues parameter selects whether the extreme 
    // values of ordered knob ranges should be included (the remaining percentage is distributed 
    // uniformly across ranges).
    case SelectiveProfiling(percentage: Int, extremeValues: Bool)
}
func ==(lhs: ApplicationExecutionMode, rhs: ApplicationExecutionMode) -> Bool {
    switch (lhs, rhs) {
        case (.Adaptive, .Adaptive): 
            return true
        case (.NonAdaptive, .NonAdaptive): 
            return true
        case (.ExhaustiveProfiling, .ExhaustiveProfiling): 
            return true
        case (let .SelectiveProfiling(pl, el), let .SelectiveProfiling(pr, er)):
            return pl == pr && el == er
        default:
            return false
    }
}

extension InteractionMode: InitializableFromString {

    init?(from text: String) {

        switch text {

        case "Default": 
            self = InteractionMode.Default

        case "Scripted": 
            self = InteractionMode.Scripted

        default:
            return nil

        }
    }
}

extension InteractionMode: CustomStringConvertible {

    var description: String {

        switch self {

        case InteractionMode.Default: 
            return "Default"

        case InteractionMode.Scripted: 
            return "Scripted"
        
        }
    }
}

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

        Runtime.runtimeKnobs             = RuntimeKnobs()

        Runtime.scenarioKnobs            = ScenarioKnobs()

        Runtime.scriptedCounter          = 0

        Runtime.shouldTerminate          = false

        Runtime.apiModule                = RuntimeApiModule()
    }

    internal static let restServerPort    = initialize(type: UInt16.self, name: "port",    from: key, or: 1338)
    internal static let restServerAddress = initialize(type: String.self, name: "address", from: key, or: "0.0.0.0")
    // Controls whether or not the test harness is involved in the execution. 
    // This includes obtaining initialization parameters are obtained from response to post to brass-th/ready, 
    // and posting to brass-th/status after the processing of each input.
    internal static let executeWithTestHarness = initialize(type: Bool.self, name: "executeWithTestHarness", from: key, or: false)

    private static var measures: [String : Double] = [:]
    private static var measuresLock = NSLock()
    internal static var measuringDevices: [String : MeasuringDevice] = [:]

    internal static var knobSetters: [String : (Any) -> Void] = [:]
    internal static var knobSettersLock = NSLock()

    internal static var intents: [String : IntentSpec] = [:]
    internal static var models: [String : Model] = [:]
    internal static var controller: Controller = ConstantController()
    internal static var controllerLock = NSLock()

    internal static let intentCompiler = Compiler()

    /** 
     * Fetch an intent from the cache, or, if it has not been accessed previously, 
     * load it from the file system. The intent will be loaded from a file whose
     * name is <APPLICATION_PATH>/<ID>.intent, where <APPLICATION_PATH> is the 
     * location of the application and <ID> is the value of the id parameter. 
     */
    public static func loadIntent(_ id: String) -> IntentSpec? {
        if let intentFileContent = readFile(withName: id, ofType: "intent") {
            let intent = intentCompiler.compileIntentSpec(source: intentFileContent)
            if let i = intent { 
                setIntent(i)
            }
            return intent
        }
        else {
            Log.debug("Unable to load intent '\(id)'.")
            return nil
        }
    }

    internal static func setIntent(_ spec: IntentSpec) {
        synchronized(controllerLock) {
            intents[spec.name] = spec
            Log.info("Changed intent '\(spec.name)' to: \(spec)")
        }
    }

    /** 
     * Fetch a model from the cache, or, if it has not been accessed previously, 
     * load it from the file system. The model will be loaded from two files whose
     * names are <APPLICATION_PATH>/<ID>.knobtable, and 
     * <APPLICATION_PATH>/<ID>.measuretable where <APPLICATION_PATH> is the 
     * location of the application and <ID> is the value of the id parameter. 
     */
    public static func loadModel(_ id: String, _ initialConfigurationIndex: Int = 0) -> Model? {
        if let model = models[id] {
            return model
        }
        else {
            if let knobCSV = readFile(withName: id, ofType: "knobtable") {
                if let measureCSV = readFile(withName: id, ofType: "measuretable") {
                    let model = Model(knobCSV, measureCSV, initialConfigurationIndex)
                    synchronized(controllerLock) {
                        models[id] = model
                    }
                    return model   
                }
                else {
                    Log.error("Unable to load measure table \(id).measuretable.")
                    return nil
                }    
            }
            else {
                Log.error("Unable to load knob table \(id).knobtable.")
                return nil
            }
        }
    }

//------------------- very new stuff

    // The runtime registers the APIs of the platform and application 
    internal static var architecture: Architecture? = DefaultArchitecture()
    internal static var application: Application? = nil

    // The runtime manages communcations e.g. TCP
    internal static var communicationChannel: CommunicationServer? = nil

    static func shutdown() -> Void {
        // TODO implement global exit, now only the server thread quits
        exit(0)
    }

    static public func establishCommuncationChannel(port: Int = 1337) {

        Runtime.communicationChannel = TcpSocketServer(port: port)
        Runtime.communicationChannel!.run(MessageHandler())
    }

    // These knobs control the interaction mode (e.g. scripted) and application execution mode (e.g. profiling)
    class RuntimeKnobs: TextApiModule {

        let name = "RuntimeKnobs"

        var subModules = [String : TextApiModule]()

        var interactionMode: Knob<InteractionMode>

        var applicationExecutionMode: Knob<ApplicationExecutionMode>

        init() {
            self.interactionMode = Knob(name: "interactionMode", from: key, or: InteractionMode.Default, preSetter: Runtime.changeInteractionMode)
            self.applicationExecutionMode = Knob(name: "applicationExecutionMode", from: key, or: ApplicationExecutionMode.Adaptive)
            self.addSubModule(newModule: interactionMode)
            self.addSubModule(newModule: applicationExecutionMode)
        }
    }

    static var runtimeKnobs: RuntimeKnobs = RuntimeKnobs()

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
                    let windowAverages = measuringDevice.windowAverages()
                    let constraintMeasureValue = windowAverages[intents[intentName]!.constraintName]!
                    return ( intentName, [ "constraintMeasureValue" : constraintMeasureValue ] )
                })

            var arguments : [String : Any] =
                [ "application"              : application
                , "applicationKnobs"         : toArrayOfPairDicts(applicationKnobs)
                , "architecture"             : architecture
                , "systemConfigurationKnobs" : toArrayOfPairDicts(systemConfigurationKnobs)
                , "scenarioKnobs"            : toArrayOfPairDicts(scenarioKnobs)
                , "measures"                 : toArrayOfPairDicts(Runtime.getMeasures())
                , "intents"                  : Dictionary(intents.map{ (n,i) in (n,i.toJson()) })
                , "verdictComponents"        : verdictComponents
                ] 

            // The measure values that the controller associates with the current configuration
            let currentKnobSettingsId = Int(Runtime.getMeasure("currentConfiguration")!) // kid of the currently active KnobSettings
            if let currentConfiguration = models[application]!.configurations.first(where: { $0.knobSettings.kid == currentKnobSettingsId }) {
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

    // These knobs simulate changes to the environment during a test
    class ScenarioKnobs: TextApiModule {

        let name = "scenarioKnobs"

        var subModules = [String : TextApiModule]()

        // Number of inputs to be processed across a mission
        var missionLength: Knob<UInt64>
        // Parameter (with range [0.0,1.0]) used to introduce noise in the input
        var sceneObfuscation: Knob<Double>

        init() {
            self.missionLength    = Knob(name: "missionLength",    from: key, or: 1000, preSetter: { assert((0...1000).contains($1)) })
            self.sceneObfuscation = Knob(name: "sceneObfuscation", from: key, or: 0.0,  preSetter: { assert((0.0...1.0).contains($1)) })
            self.addSubModule(newModule: missionLength)
            self.addSubModule(newModule: sceneObfuscation)
        }

    }

    static var scenarioKnobs: ScenarioKnobs = ScenarioKnobs()

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

    // The runtime API this where the channel connects
    public class RuntimeApiModule: TextApiModule {
        public let name = "Runtime"
        public var subModules = [String : TextApiModule]()

        public func internalTextApi(caller:            String, 
                                    message:           Array<String>, 
                                    progressIndicator: Int, 
                                    verbosityLevel:    VerbosityLevel) -> String {

            // the internal runtime API handles the process command
            if message[progressIndicator] == "process" {

                if Runtime.runtimeKnobs.interactionMode.get() == InteractionMode.Scripted {

                    if message.count > progressIndicator + 1 {
                
                        let nextWord = message[progressIndicator + 1]
                        var stepAmount: UInt64 = 0

                        if nextWord == "random" {

                            if message.count > progressIndicator + 3 {
                                
                                if  let loBound = Int(message[progressIndicator + 2]),
                                    let hiBound = Int(message[progressIndicator + 3]) {
                                        
                                        stepAmount = UInt64(randi(1, 1, min: loBound, max: hiBound)[0, 0])
                                }
                            }

                        } else if let stepNumber = UInt64(message[progressIndicator + 1]) {

                            stepAmount = stepNumber
                        }

                        if stepAmount > 0 {

                            Runtime.process(numberOfInputs: stepAmount)

                            switch verbosityLevel {

                                case VerbosityLevel.Verbose:
                                    return "Processed \(stepAmount) input(s)."
                            
                                default:
                                    return ""
                            }

                        } else {

                            switch verbosityLevel {

                                case VerbosityLevel.Verbose:
                                    return "Invalid step amount for process: ``" + message.joined(separator: " ") + "`` received from: \(caller)."
                            
                                default:
                                    return ""
                            }
                        }
                    }

                } else {

                    switch verbosityLevel {

                        case VerbosityLevel.Verbose:
                            return "Invalid process message: ``" + message.joined(separator: " ") + "`` received from: \(caller) as interactionMode is \(Runtime.runtimeKnobs.interactionMode.get())."
                    
                        default:
                            return ""
                    }
                }

            // the runtime keeps track of the iteration measure
            } else if message[progressIndicator] == "iteration" && message[progressIndicator + 1] == "get" {

                switch verbosityLevel {
                
                    case VerbosityLevel.Verbose:
                        return "Current iteration is: " + String(describing: Runtime.getMeasure("iteration")) + "."
                    
                    default:
                        return String(describing: Runtime.getMeasure("iteration"))
                }                

            // invalid message
            } else {

                switch verbosityLevel {
                
                    case VerbosityLevel.Verbose:
                        return "Invalid message: ``" + message.joined(separator: " ") + "'' received from: \(caller)."
                    
                    default:
                        return ""
                }
            }

            // TODO we should not get here
            return "Alalala"
        }

        /** get status as a dictionary */
        public func getInternalStatus() -> [String : Any]? {
            return ["iteration" : UInt64(Runtime.getMeasure("iteration")!)] // TODO make sure iteration is always defined, some global init would be nice
        }

        init() {
            self.addSubModule(newModule: runtimeKnobs)
        }
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
            setIntent(spec)
            // FIXME Check that the model and updated intent are consistent (that measure and knob sets coincide)
            initializeController(model, spec, Runtime.controller.window)
        }
        else {
            Log.warning("Attempt to reinitialize controller based on a controller with an undefined model.")
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
    internal static func getMeasure(_ name: String) -> Double? {
        return measures[name]
    }

    /** Get the current values of all measures */
    internal static func getMeasures() -> [String : Double] {
        return measures
    }    

    /** Update the value of name in the global measure store and return that value */
    internal static func setKnob(_ name: String, to value: Any) {
        if let setKnobTo = knobSetters[name] {
            setKnobTo(value)
        }
        else {
            fatalError("Tried to assign \(value) to an unknown knob called \(name).")
        }    
    }

}

////////////////
// Monitoring //
////////////////

/* Execute routine and update the progress counter. */
internal func executeAndReportProgress(_ m: MeasuringDevice, _ routine: (Void) -> Void) {
    routine()
    m.reportProgress()
}

/* Periodically sample measures, according to the samplingPolicy passed at 
   initialization, and compute statistics for them. */
internal class MeasuringDevice {

    private var progress: UInt32 = 0 // possibly used by a sampling policy to choose when to sample
    private var windowSize: UInt32 = 20
    private var applicationMeasures: Array<String>
    private var samplingPolicy: SamplingPolicy

    internal var stats = [String : Statistics]()

    init(_ samplingPolicy: SamplingPolicy, _ windowSize: UInt32, _ applicationMeasures: [String]) {
        self.windowSize = windowSize
        self.applicationMeasures = applicationMeasures
        self.samplingPolicy = samplingPolicy
        samplingPolicy.registerSampler(sample)
        let systemMeasures = Runtime.architecture?.systemMeasures
        for m in applicationMeasures + (systemMeasures == nil ? [String]() : systemMeasures!) {
            stats[m] = Statistics(measure: m, windowSize: Int(windowSize))
        }
    }

    public func sample() {
        for (m,s) in stats { 
            if let measure = Runtime.getMeasure(m) {
                s.observe(measure)
            }            
        }
    }

    public func windowAverages() -> [String : Double] {
        return Dictionary(stats.map{ (n,s) in (n, s.windowAverage) })
    }

    func reportProgress() {
        progress += 1
        samplingPolicy.reportProgress(progress)
    }

}

//---------------------------------------
