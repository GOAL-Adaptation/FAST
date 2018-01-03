/* Periodically sample measures, according to the samplingPolicy passed at
   initialization, and compute statistics for them. */
class MeasuringDevice {
    private var progress: UInt32 = 0 // possibly used by a sampling policy to choose when to sample
    private var windowSize: UInt32 = 20
    private var applicationMeasures: Array<String>
    private var samplingPolicy: SamplingPolicy

    var stats = [String : Statistics]()

    init(_ samplingPolicy: SamplingPolicy, _ windowSize: UInt32, _ applicationMeasures: [String]) {
        self.windowSize = windowSize
        self.applicationMeasures = applicationMeasures
        self.samplingPolicy = samplingPolicy
        samplingPolicy.registerSampler(sample)
        let systemMeasures = Runtime.architecture?.systemMeasures ?? []
        for m in applicationMeasures + systemMeasures {
            stats[m] = Statistics(measure: m, windowSize: Int(windowSize))
        }
    }

    public func sample() {
        for (m,s) in stats {
            if let measure = Runtime.getMeasure(m) {
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
