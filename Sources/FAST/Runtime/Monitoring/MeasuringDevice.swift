/* Periodically sample measures, according to the samplingPolicy passed at
   initialization, and compute statistics for them. */
class MeasuringDevice {
    private var progress: UInt32 = 0 // possibly used by a sampling policy to choose when to sample
    private var windowSize: UInt32 = 20
    private var applicationMeasures: Array<String>
    private var samplingPolicy: SamplingPolicy
    private unowned var runtime: Runtime

    // Overall statistics, across all inputs/configurations
    var stats = [String : Statistics]()
    // Per-KnobSettings (configuration) statistics
    var statsPerKnobSettings = [String : [KnobSettings : Statistics]]()

    init(_ samplingPolicy: SamplingPolicy, _ windowSize: UInt32, _ applicationMeasures: [String], _ runtime: Runtime) {
        self.windowSize = windowSize
        self.applicationMeasures = applicationMeasures
        self.samplingPolicy = samplingPolicy
        self.runtime = runtime
        samplingPolicy.registerSampler(sample)
        
        for m in Array(Set(applicationMeasures + runtime.runtimeAndSystemMeasures)).sorted() {
            stats[m] = Statistics(measure: m, windowSize: Int(windowSize))
            statsPerKnobSettings[m] = [KnobSettings : Statistics]()
        }
    }

    public func sample() {
        for (m,s) in stats {
            if let measure = runtime.getMeasure(m) {
                s.observe(measure)
                // If running in Adaptive or MachineLearning mode, track statistics per configuration
                if 
                    let currentConfiguration = runtime.getCurrentConfiguration(),
                    var perKnobSettingsStatsForM = statsPerKnobSettings[m]
                {
                    if let statsForCurrentKnobSettings = perKnobSettingsStatsForM[currentConfiguration.knobSettings] {
                        statsForCurrentKnobSettings.observe(measure)
                    }
                    else {
                        let statsForCurrentKnobSettings = Statistics(measure: m, windowSize: Int(windowSize))
                        perKnobSettingsStatsForM[currentConfiguration.knobSettings] = statsForCurrentKnobSettings
                        statsForCurrentKnobSettings.observe(measure)
                    }
                }
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
