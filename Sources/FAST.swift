/**

  FAST: A library for implicit programming.

*/

import Foundation
import Venice
import CEnergymon

////////////////
// Monitoring //
////////////////

class Measure<T> {
    var value: T
    init(value: T) {
        self.value = value

    }
    func get() -> T {
        return value
    }
}
class Knob<T> : Measure<T> {
    internal func set(value: T) {
        self.value = value
    }
}

/** Global measure store */
private var measures: [String: Double] = [:]
private var measuresLock = NSLock()

@discardableResult public func measure(_ label: String, _ m: Double) -> Double {
    synchronized(measuresLock) {
        measures[label] = m
    }
    return m
}

internal func monitor(_ m: MeasuringDevice, _ routine: (Void) -> Void) {
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
        monitor(m, routine)
    }
}

public protocol SamplingPolicy {

    func registerSampler(_ sample: @escaping () -> Void) -> Void

    func reportProgress(_ progress: UInt) -> Void

}

/** Sample once per N seconds, where N is the samplingRate passed to init(). */
public class TimingSamplingPolicy : SamplingPolicy {

    let samplingRate: Double

    init(_ samplingRate: Double) {
        self.samplingRate = samplingRate
    }

    /** Runs sample() once per N seconds, where N is the samplingRate passed to init(). */
    public func registerSampler(_ sample: @escaping () -> Void) -> Void {
        co {
            while true {
                sample()
                nap(for: self.samplingRate)
            }
        }
    }

    /** Ignored. Sampling is done purely based on time. */
    public func reportProgress(_ progress: UInt) -> Void {}

}

/** Sample once per N calls to reportProgress(), where N is the period passed to init(). */
public class ProgressSamplingPolicy : SamplingPolicy {

    private let period: UInt
    private var sample: () -> Void = { }

    init(period: UInt) {
        self.period = period
    }

    public func registerSampler(_ sample: @escaping () -> Void) -> Void {
        self.sample = sample
    }

    /** Calls sample once per N invocations, where N is the period passed to init(). */
    public func reportProgress(_ progress: UInt) -> Void {
        if progress % period == 0 {
            self.sample()
        }
    }

}

protocol EnergyMonitor {

    /** Returns the current energy in microjoules */
    func read() -> UInt64

}

class CEnergyMonitor : EnergyMonitor {

    var em = energymon()

    /** Get the energymon instance and initialize */
    init() {
        let _ = energymon_get_default(&em)
        let _ = em.finit(&em)
    }

    /** Returns the current energy in microjoules */
    func read() -> UInt64 {
        return em.fread(&em)
    }

    /** Destroy the energymon instance */
    deinit {
        let _ = em.ffinish(&em)
    }

}

class MeasuringDevice {

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

/**
    Computes total and window statistics for a single quantity,
    using constant-time algorithms.

    - Cumulative moving average is computed over all observed values.
    - Window average is computed over the N latest observations,
      where N is the windowSize passed to init().
*/
class Statistics {

    private var _totalAverage: Double = 0
    private var totalCount: Int = 0

    private var _windowAverage: Double = 0
    private var window: [Double] = []
    private var windowHead: Int = 0
    private var windowIsComplete: Bool = false
    private var windowLock: NSLock = NSLock()

    /** Returns the cumulative moving average, computed over all observations. */
    var totalAverage: Double {
        get { return _totalAverage }
    }

    /** Returns the moving average, computed over the last N observations, where
        N is the windowSize passed to init(). When less than windowSize
        observations have been made, returns Double.nan. */
    var windowAverage: Double {
        get { return windowIsComplete ? _windowAverage : Double.nan }
    }

    init(windowSize: Int) {
        precondition(windowSize > 0, "Window size must be positive")
        window = Array(repeating: Double.nan, count: windowSize)
    }

    /**
        NB: The new window size must not be greater than the current window size.
        NB: Linear in windowSize.
    */
    var windowSize: Int {
        get {
            return window.count
        }
        set(newSize) {
            precondition(newSize > 0, "Window size must be positive")
            precondition(windowSize >= newSize, "Window size can not grow")
            synchronized(windowLock) {
                var newWindow = Array(repeating: 0.0, count: newSize)
                for i in 0 ..< newSize {
                    newWindow[i] = window[windowHead + i % windowSize]
                }
                window = newWindow
                _windowAverage = window.reduce(0.0, +) / Double(newSize)
            }
        }
    }

    /** Update statistics */
    @discardableResult func observe(_ value: Double) -> Double {
        /* Total average */
        _totalAverage = cumulativeMovingAverage(current: _totalAverage, count: totalCount, newValue: value)
        totalCount += 1
        synchronized(windowLock) {
            /* Window average */
            if windowIsComplete {
                _windowAverage = _windowAverage + (value - window[windowHead]) / Double(windowSize)
            }
            else {
                _windowAverage = cumulativeMovingAverage(current: _windowAverage, count: windowHead, newValue: value)
                if windowHead == windowSize - 1 {
                    windowIsComplete = true
                }
            }
            window[windowHead] = value
            windowHead = (windowHead + 1) % windowSize
        }
        return value
    }

    @inline(__always) private func cumulativeMovingAverage(current: Double, count: Int, newValue: Double) -> Double {
        return (current * Double(count) + newValue) / Double(count + 1)
    }

}

//////////////////
// Optimization //
//////////////////

/** Global intent store */
private var intents: [String: Intent] = [:]
private var intentsLock = NSLock()

typealias KnobName = String
typealias KnobValue = String

class KnobSettings {

    let settings: [KnobName: KnobValue]

    init(settings: [KnobName: KnobValue]) {
        self.settings = settings
    }

    func apply() {
        for (knobName, knobValue) in settings {
            // TODO applu knob settings
        }
    }

}

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

public func optimize
    ( _ id: String
    , across windowSize: UInt
    , samplingPolicy: SamplingPolicy = TimingSamplingPolicy(100.millisecond)
    , _ labels: [String]
    , _ routine: (Void) -> Void) {

    let intent = intents[id]

    let m = MeasuringDevice(samplingPolicy, windowSize, labels)

    func computeStrategy() -> KnobSettingStrategy {
        // FIXME Replace dummy strategy
        return KnobSettingStrategy(strategy: { (_: UInt) -> KnobSettings in return KnobSettings(settings: [:]) })
    }

    var progress: UInt = 0 // progress counter distinct from that used in ProgressSamplingPolicy
    var strategy: KnobSettingStrategy = computeStrategy()
    while true {
        monitor(m, routine)
        progress += 1
        if progress % windowSize == 0 {
            strategy = computeStrategy()
        }
        // FIXME This should only apply when the strategy actually needs to change knobs
        strategy[progress % windowSize].apply()
    }

}

///////////////
// Utilities //
///////////////

func synchronized<L: NSLocking>(_ lock: L, routine: () -> ()) {
    lock.lock()
    routine()
    lock.unlock()
}
