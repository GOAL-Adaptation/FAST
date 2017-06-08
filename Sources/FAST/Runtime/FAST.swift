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

/* Global intent store */
private var intents: [String : IntentSpec] = [:]
private var intentsLock = NSLock()

public func setIntent(_ name: String, _ intent: IntentSpec) {
    synchronized(intentsLock) {
        intents[name] = intent
    }
}

/* Global measure store */
internal var measures: [String : Double] = [:]
private var measuresLock = NSLock()

/* Global knob setter store */
internal var knobSetters: [String : (Any) -> Void] = [:]
private var knobSettersLock = NSLock()

/* Global controller */
internal var controller: Controller = ConstantController()
private var controllerLock = NSLock()

public func initializeController(_ model: Model, _ intent: IntentSpec, _ window: UInt32 = 20) {
    synchronized(controllerLock) {
        controller = IntentPreservingController(model, intent, window)
    }
}

/* Wrapper for a value that can be read freely, but can only be changed by the runtime. */
public class Knob<T> {
    var v: T
    public init(_ name: String, _ v: T) {
        self.v = v
        knobSetters[name] = { (a: Any) -> Void in
            switch a {
            case let vv as T:
                self.v = vv
            default:
                fatalError("Tried to assign \(a) to a knob of type \(type(of: v)).")
            }
        }
    }
    public func get() -> T {
        return self.v
    }
    internal func set(_ v: T) {
        self.v = v
    }
}

/* Update the value of name in the global measure store and return that value. */
internal func setKnob(_ name: String, to value: Any) {
    if let setKnobTo = knobSetters[name] {
        setKnobTo(value)
    }
    else {
        fatalError("Tried to assign \(value) to an unknown knob called \(name).")
    }    
}

/* Update the value of name in the global measure store and return that value. */
@discardableResult public func measure(_ name: String, _ value: Double) -> Double {
    synchronized(measuresLock) {
        measures[name] = value
    }
    Log.verbose("Registered value \(value) for measure \(name).")
    return value
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

    private var progress: UInt32 = 0
    private var windowSize: UInt32 = 20
    private var applicationMeasures: Array<String>
    private var systemMeasures: Array<String> = ["energy", "time"]
    private var samplingPolicy: SamplingPolicy
    private let energyMonitor: EnergyMonitor = CEnergyMonitor()
    private var energy: UInt64 = 0

    private var stats = [String : Statistics]()

    init(_ samplingPolicy: SamplingPolicy, _ windowSize: UInt32, _ applicationMeasures: [String]) {
        self.windowSize = windowSize
        self.applicationMeasures = applicationMeasures
        self.samplingPolicy = samplingPolicy
        samplingPolicy.registerSampler(sample)
        for m in applicationMeasures + systemMeasures {
            stats[m] = Statistics(windowSize: Int(windowSize))
        }
        /* System measures */
        energy = self.energyMonitor.read()
        co {
            while true {
                let energyNow = self.energyMonitor.read()
                let (deltaEnergy, _) = UInt64.subtractWithOverflow(energyNow, self.energy)
                let _ = measure("energy", Double(deltaEnergy))
                self.energy = energyNow
                let _ = measure("time", NSDate().timeIntervalSince1970)
                nap(for: 1.millisecond)
            }
        }
    }

    public func sample() {
        for (m,s) in stats { s.observe(measures[m]!) }
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
            setKnob(name, to: value)
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
    
    if let intent = intents[id] {
        let m = MeasuringDevice(samplingPolicy, windowSize, labels)
        var progress: UInt32 = 0 // progress counter distinct from that used in ProgressSamplingPolicy
        var schedule: Schedule = Schedule(constant: controller.model.getInitialConfiguration()!.knobSettings)
        while true {
            executeAndReportProgress(m, routine)
            progress += 1
            if progress % windowSize == 0 {
                schedule = controller.getSchedule(intent, measures)
            }
            // FIXME This should only apply when the schedule actually needs to change knobs
            schedule[progress % windowSize].apply()
        }
    } else {
        Log.warning("No intent defined for optimize scope \"\(id)\". Proceeding without adaptation.")
    }   

}