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
