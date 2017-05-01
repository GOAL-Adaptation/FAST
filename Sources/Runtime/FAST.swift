/**

  FAST: A library for implicit programming.

*/

import Foundation
import Venice
import HeliumLogger
import LoggerAPI
import Intent

///////////////////
// Runtime State //
///////////////////

let logger = HeliumLogger()

/* Global measure store */
private var intents: [String: IntentSpec] = [:]
private var intentsLock = NSLock()

/* Global measure store */
private var measures: [String: Double] = [:]
private var measuresLock = NSLock()

/* Global knob setter store */
private var knobSetters: [String: (Any) -> Void] = [:]
private var knobSettersLock = NSLock()

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
    ( across windowSize: UInt
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

    private var progress: UInt = 0
    private var windowSize: UInt = 20
    private var applicationMeasures: Array<String>
    private var systemMeasures: Array<String> = ["energy", "time"]
    private var samplingPolicy: SamplingPolicy
    private let energyMonitor: EnergyMonitor = CEnergyMonitor()
    private var energy: UInt64 = 0

    private var stats = [String : Statistics]()

    init(_ samplingPolicy: SamplingPolicy, _ windowSize: UInt, _ applicationMeasures: [String]) {
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
    let settings: [String: Any]
    init(settings: [String: Any]) {
        self.settings = settings
    }
    func apply() {
        for (name, value) in settings {
            setKnob(name, to: value)
        }
    }
}

/* A strategy for switching between KnobSettings, based on the input index. */
class KnobSettingStrategy {
    let strategy: (_ progress: UInt) -> KnobSettings
    init(strategy: @escaping (_ progress: UInt) -> KnobSettings) {
        self.strategy = strategy
    }
    subscript(index: UInt) -> KnobSettings {
        get {
            return strategy(index)
        }
    }
}

/* Defines an optimization scope. Replaces a loop in a pure Swift program. */
public func optimize
    ( _ id: String
    , across windowSize: UInt
    , samplingPolicy: SamplingPolicy = TimingSamplingPolicy(100.millisecond)
    , _ labels: [String]
    , _ routine: (Void) -> Void) {

    if let intent = intents[id] {
        let m = MeasuringDevice(samplingPolicy, windowSize, labels)

        func computeStrategy() -> KnobSettingStrategy {
            // FIXME Replace dummy strategy
            return KnobSettingStrategy(strategy: { (_: UInt) -> KnobSettings in return KnobSettings(settings: [:]) })
        }

        var progress: UInt = 0 // progress counter distinct from that used in ProgressSamplingPolicy
        var strategy: KnobSettingStrategy = computeStrategy()
        while true {
            executeAndReportProgress(m, routine)
            progress += 1
            if progress % windowSize == 0 {
                strategy = computeStrategy()
            }
            // FIXME This should only apply when the strategy actually needs to change knobs
            strategy[progress % windowSize].apply()
        }
    } else {
        Log.warning("No intent defined for optimize scope \"\(id)\". Proceeding without adaptation.")
    }   

}