/* Periodically sample measures, according to the samplingPolicy passed at
   initialization, and compute statistics for them. */
class MeasuringDevice {
    private var progress: UInt32 = 0 // possibly used by a sampling policy to choose when to sample
    private var windowSize: UInt32 = 20
    private var applicationMeasures: Array<String>
    private var samplingPolicy: SamplingPolicy
    private unowned var runtime: Runtime

    var stats = [String : Statistics]()

    init(_ samplingPolicy: SamplingPolicy, _ windowSize: UInt32, _ applicationMeasures: [String], _ runtime: Runtime) {
        self.windowSize = windowSize
        self.applicationMeasures = applicationMeasures
        self.samplingPolicy = samplingPolicy
        self.runtime = runtime
        samplingPolicy.registerSampler(sample)
        
        for m in Array(Set(applicationMeasures + runtime.runtimeAndSystemMeasures)).sorted() {
            stats[m] = Statistics(measure: m, windowSize: Int(windowSize))
        }
    }

    public func sample() {
        for (m,s) in stats {
            if let measure = runtime.getMeasure(m) {
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
