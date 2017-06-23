/**

  FAST: A library for implicit programming.

*/

import Foundation
import Venice

import HeliumLogger
import LoggerAPI
import CSwiftV

///////////////////
// Runtime State //
///////////////////

let logger = HeliumLogger()

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

    internal func set(_ newValue: T) {
        // for the postSetter
        let oldValue = self.value

        self.preSetter(oldValue, newValue)
        self.value = newValue
        self.postSetter(oldValue, newValue)
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

public class Runtime {

    private init() {}

    fileprivate static var measures: [String : Double] = [:]
    private static var measuresLock = NSLock()

    fileprivate static var knobSetters: [String : (Any) -> Void] = [:]
    private static var knobSettersLock = NSLock()

    fileprivate static var intents: [String : IntentSpec] = [:]
    fileprivate static var controller: Controller = ConstantController()
    private static var controllerLock = NSLock()

//------------------- very new stuff
    internal static var architecture: Architecture? = nil
    internal static var application: Application? = nil

    internal static var communicationChannel: CommunicationServer? = nil

    static func shutdown() -> Void {
        // TODO implement global exit, now only the server thread quits
        exit(0)
    }

    static public func establishCommuncationChannel(port: Int) {

        Runtime.communicationChannel = TcpSocketServer(port: port)
        Runtime.communicationChannel!.run(MessageHandler())
    }

    public class RuntimeApiModule: TextApiModule {
        public var subModules = [String : TextApiModule]()
        init() {}
    }

    public static var apiModule = RuntimeApiModule()

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

    public static func registerApplication(application: Application) {

        self.application = application

        reregisterSubModules()
    }

    static func reregisterSubModules() -> Void {
        apiModule.subModules = [String : TextApiModule]()
        if let architecture = self.architecture {
            apiModule.addSubModule(newModule: architecture)
        }
        if let application = self.application {
            apiModule.addSubModule(newModule: application)
        }
    }
//------------------- end of very new stuff

    /** Intialize intent preserving controller with the given model, intent and window */
    public static func initializeController(_ model: Model, _ intent: IntentSpec, _ window: UInt32 = 20) {
        synchronized(controllerLock) {
            intents[intent.name] = intent
            controller = IntentPreservingController(model, intent, window)
        }
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
    , across windowSize: UInt32
    , samplingPolicy: SamplingPolicy = TimingSamplingPolicy(100.millisecond)
    , _ labels: [String]
    , _ routine: (Void) -> Void) {
    
    if let intent = Runtime.intents[id] {
        let m = MeasuringDevice(samplingPolicy, windowSize, labels)
        // FIXME what if the counter overflows
        var iteration: UInt32 = 0 // iteration counter
        var schedule: Schedule = Schedule(constant: Runtime.controller.model.getInitialConfiguration()!.knobSettings)
        while true {
            Runtime.measure("iteration", Double(iteration))
            executeAndReportProgress(m, routine)
            iteration += 1
            if iteration % windowSize == 0 {
                schedule = Runtime.controller.getSchedule(intent, Runtime.measures)
            }
            // FIXME This should only apply when the schedule actually needs to change knobs
            schedule[iteration % windowSize].apply()
            Runtime.measure("iteration", Double(iteration))
        }
    } else {
        Log.warning("No intent defined for optimize scope \"\(id)\". Proceeding without adaptation.")
    }   

}