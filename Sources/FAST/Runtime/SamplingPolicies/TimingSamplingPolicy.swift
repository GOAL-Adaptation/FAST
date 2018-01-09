import Foundation
import Dispatch

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
