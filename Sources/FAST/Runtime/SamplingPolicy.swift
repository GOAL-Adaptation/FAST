/**

  A sampling policy decides whether or not a sampling function should be
  called when the application has processed an input.

*/

import Venice

public protocol SamplingPolicy {

    /** Initialize policy with sampling function. */
    func registerSampler(_ sample: @escaping () -> Void) -> Void

    /** Called by the runtime every time application processes an input, giving the policy
        the chance to call the sample function that was passed to registerSampler */
    func reportProgress(_ progress: UInt32) -> Void

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
    public func reportProgress(_ progress: UInt32) -> Void {}

}

/** Sample once per N calls to reportProgress(), where N is the period passed to init(). */
public class ProgressSamplingPolicy : SamplingPolicy {

    private let period: UInt32
    private var sample: () -> Void = { }

    init(period: UInt32) {
        self.period = period
    }

    public func registerSampler(_ sample: @escaping () -> Void) -> Void {
        self.sample = sample
    }

    /** Calls sample once per N invocations, where N is the period passed to init(). */
    public func reportProgress(_ progress: UInt32) -> Void {
        if progress % period == 0 {
            self.sample()
        }
    }

}