/**

  A sampling policy decides whether or not a sampling function should be
  called when the application has processed an input.

*/

import Foundation
import Dispatch

public protocol SamplingPolicy {

    /** Initialize policy with sampling function. */
    func registerSampler(_ sample: @escaping () -> Void) -> Void

    /** Called by the runtime every time application processes an input, giving the policy
        the chance to call the sample function that was passed to registerSampler */
    func reportProgress(_ progress: UInt32) -> Void

}

/** Sample once per N seconds, where N is the samplingPeriod passed to init(). */
public class TimingSamplingPolicy : SamplingPolicy {

    let samplingPeriod: Double

    public init(_ samplingPeriod: Double) {
        self.samplingPeriod = samplingPeriod
    }

    /** Runs sample() once per N seconds, where N is the samplingPeriod passed to init(). */
    public func registerSampler(_ sample: @escaping () -> Void) -> Void {
        DispatchQueue.global(qos: .utility).async {
            while true {
                sample()
                usleep(UInt32(1000000.0 * self.samplingPeriod))
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

    public init(period: UInt32) {
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