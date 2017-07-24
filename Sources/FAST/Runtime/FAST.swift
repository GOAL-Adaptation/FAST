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
import Venice
import HeliumLogger
import LoggerAPI
import CSwiftV

import Nifty

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

    fileprivate static var measures: [String : Double] = [:]
    private static var measuresLock = NSLock()

    fileprivate static var knobSetters: [String : (Any) -> Void] = [:]
    private static var knobSettersLock = NSLock()

    fileprivate static var intents: [String : IntentSpec] = [:]
    fileprivate static var models: [String : Model] = [:]
    fileprivate static var controller: Controller = ConstantController()
    private static var controllerLock = NSLock()

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
                    Log.verbose("Unable to load measure table \(id).measuretable.")
                    return nil
                }    
            }
            else {
                Log.verbose("Unable to load knob table \(id).knobtable.")
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

    static public func establishCommuncationChannel(port: Int) {

        Runtime.communicationChannel = TcpSocketServer(port: port)
        Runtime.communicationChannel!.run(MessageHandler())
    }

    // These knobs control the interaction mode, e.g. scripted
    class RuntimeKnobs: TextApiModule {

        let name = "RuntimeKnobs"

        var subModules = [String : TextApiModule]()

        var interactionMode: Knob<InteractionMode>

        init() {
            self.interactionMode = Knob(name: "interactionMode", from: key, or: InteractionMode.Default, preSetter: Runtime.changeInteractionMode)
            
            self.addSubModule(newModule: interactionMode)
        }
    }

    static var runtimeKnobs: RuntimeKnobs = RuntimeKnobs()

    static func changeInteractionMode(oldMode: InteractionMode, newMode: InteractionMode) -> Void {

        // Change applies only if the value has changed
        if (oldMode != newMode) && (newMode == InteractionMode.Scripted) {
            Runtime.scriptedCounter = 0
        }
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

                            Runtime.scriptedCounter += UInt64(stepAmount)

                            while (Runtime.runtimeKnobs.interactionMode.get() == InteractionMode.Scripted && 
                                   Runtime.scriptedCounter > 0) {}

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
                        return "Current iteration is: " + String(describing: Runtime.readMeasure("iteration")) + "."
                    
                    default:
                        return String(describing: Runtime.readMeasure("iteration"))
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
            return ["iteration" : UInt64(Runtime.readMeasure("iteration")!)] // TODO make sure iteration is always defined, some global init would be nice
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

    /** Intialize intent preserving controller with the given model, intent and window */
    public static func initializeController(_ model: Model, _ intent: IntentSpec, _ window: UInt32 = 20) {
        synchronized(controllerLock) {
            controller = IntentPreservingController(model, intent, window)
        }
    }

    /** Intialize intent preserving controller with the intent, keeping the previous model and window */
    public static func reinitializeController(_ spec: IntentSpec) {
        setIntent(spec)
        // FIXME Check that the model and updated intent are consistent (that measure and knob sets coincide)
        initializeController(Runtime.controller.model, spec, Runtime.controller.window)
    }

    /** Update the value of name in the global measure store and return that value */
    @discardableResult public static func measure(_ name: String, _ value: Double) -> Double {
        synchronized(measuresLock) {
            measures[name] = value
        }
        Log.verbose("Registered value \(value) for measure \(name).")
        return value
    }

    /** Read the current value of a measure */
    public static func readMeasure(_ name: String) -> Double? {
        return measures[name]
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

public func monitor
    ( across windowSize: UInt32
    , samplingPolicy: SamplingPolicy = TimingSamplingPolicy(100.millisecond)
    , _ labels: [String]
    , _ routine: (Void) -> Void) {
    let m = MeasuringDevice(samplingPolicy, windowSize, labels)
    while true {
        executeAndReportProgress(m, routine)
    }
}

/* Periodically sample measures, according to the samplingPolicy passed at 
   initialization, and compute statistics for them. */
internal class MeasuringDevice {

    private var progress: UInt32 = 0 // possibly used by a sampling policy to choose when to sample
    private var windowSize: UInt32 = 20
    private var applicationMeasures: Array<String>
    private var samplingPolicy: SamplingPolicy

    private var stats = [String : Statistics]()

    init(_ samplingPolicy: SamplingPolicy, _ windowSize: UInt32, _ applicationMeasures: [String]) {
        self.windowSize = windowSize
        self.applicationMeasures = applicationMeasures
        self.samplingPolicy = samplingPolicy
        samplingPolicy.registerSampler(sample)
        let systemMeasures = Runtime.architecture?.systemMeasures
        for m in applicationMeasures + (systemMeasures == nil ? [String]() : systemMeasures!) {
            stats[m] = Statistics(windowSize: Int(windowSize))
        }
    }

    public func sample() {
        for (m,s) in stats { s.observe(Runtime.measures[m]!) }
    }

    func reportProgress() {
        progress += 1
        samplingPolicy.reportProgress(progress)
    }

}

//////////////////
// Optimization //
//////////////////

/* A collection of knob values that can be applied to control the system. */
class KnobSettings {
    let settings: [String : Any]
    init(_ settings: [String : Any]) {
        self.settings = settings
    }
    func apply() {
        for (name, value) in settings {
            Runtime.setKnob(name, to: value)
        }
        Log.verbose("Applied knob settings.")
    }
}

/* A strategy for switching between KnobSettings, based on the input index. */
public class Schedule {
    let schedule: (_ progress: UInt32) -> KnobSettings
    init(_ schedule: @escaping (_ progress: UInt32) -> KnobSettings) {
        self.schedule = schedule
    }
    init(constant:  KnobSettings) {
        schedule = { (_: UInt32) in constant }
    }
    subscript(index: UInt32) -> KnobSettings {
        get {
            Log.verbose("Querying schedule at index \(index)")
            return schedule(index)
        }
    }
}

/* Defines an optimization scope. Replaces a loop in a pure Swift program. */
public func optimize
    ( _ id: String
    , across windowSize: UInt32 = 20
    , samplingPolicy: SamplingPolicy = TimingSamplingPolicy(100.millisecond)
    , _ labels: [String]
    , _ routine: (Void) -> Void ) {

    // Start the REST server in a low-priority background thread
    DispatchQueue.global(qos: .utility).async {
        RestServer()
    }

    let loop = { (body: (Void) -> Void) in
        while !Runtime.shouldTerminate {
            body()
        }
    }
    
    if let intent = Runtime.loadIntent(id) {
        if let model = Runtime.loadModel(id) {
            // Initialize the controller with the knob-to-mesure model, intent and window size
            Runtime.initializeController(model, intent, windowSize)
            // Initialize measuring device, that will update measures based on the samplingPolicy
            let m = MeasuringDevice(samplingPolicy, windowSize, labels)
            // FIXME what if the counter overflows
            var iteration: UInt32 = 0 // iteration counter
            var schedule: Schedule = Schedule(constant: Runtime.controller.model.getInitialConfiguration()!.knobSettings)
            loop {
                Runtime.measure("iteration", Double(iteration))
                executeAndReportProgress(m, routine)
                iteration += 1
                if iteration % windowSize == 0 {
                    schedule = Runtime.controller.getSchedule(intent, Runtime.measures)
                }
                // FIXME This should only apply when the schedule actually needs to change knobs
                schedule[iteration % windowSize].apply()
                Runtime.measure("iteration", Double(iteration))
                // FIXME maybe stalling in scripted mode should not be done inside of optimize but somewhere else in an independent and better way
                Runtime.reportProgress()
            }  
            
        } else {
            Log.warning("No model loaded for optimize scope '\(id)'. Proceeding without adaptation.")
            loop(routine)
        }        
    } else {
        Log.warning("No intent loaded for optimize scope '\(id)'. Proceeding without adaptation.")
        loop(routine)
    }

    print("FAST application terminating.")

}

//---------------------------------------
