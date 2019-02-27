import Foundation

fileprivate let key = ["proteus","runtime"]

/* Periodically sample measures, according to the samplingPolicy passed at
   initialization, and compute statistics for them. */
class MeasuringDevice {
    private var progress: UInt32 = 0 // possibly used by a sampling policy to choose when to sample
    private var windowSize: UInt32 = 20
    private var applicationMeasures: Array<String>
    private var samplingPolicy: SamplingPolicy
    private unowned var runtime: Runtime

    private let sortedMeasureNames: [String]!
    
    // Overall statistics, across all inputs/configurations
    var stats = [String : Statistics]()
    // Per-KnobSettings (configuration) statistics
    var statsPerKnobSettings = [String : [KnobSettings : Statistics]]()
    // When true, per-KnobSettings will be collected
    var collectDetailedStats: Bool

    init(_ samplingPolicy: SamplingPolicy, _ windowSize: UInt32, _ applicationMeasures: [String], _ runtime: Runtime) {
        self.windowSize = windowSize
        self.applicationMeasures = applicationMeasures
        self.samplingPolicy = samplingPolicy
        self.runtime = runtime
        self.collectDetailedStats = initialize(type: Bool.self, name: "collectDetailedStats", from: key, or: false)
        self.sortedMeasureNames = Array(Set(applicationMeasures + runtime.runtimeAndSystemMeasures)).sorted()
        
        for m in self.sortedMeasureNames {
            stats[m] = Statistics(measure: m, windowSize: Int(windowSize))
            if collectDetailedStats {
                statsPerKnobSettings[m] = [KnobSettings : Statistics]()
            }
        }
        
        samplingPolicy.registerSampler(sample)
    }

    public func sample() {
        for (m,s) in stats {
            if let measure = runtime.getMeasure(m) {
                s.observe(measure)
                if collectDetailedStats {
                    if 
                        let currentKnobSettings = runtime.currentKnobSettings,
                        var perKnobSettingsStatsForM = statsPerKnobSettings[m]
                    {
                        if let statsForCurrentKnobSettings = perKnobSettingsStatsForM[currentKnobSettings] {
                            statsForCurrentKnobSettings.observe(measure)
                        }
                        else {
                            var statsDescription: String
                            if let currentConfiguration = runtime.getCurrentConfiguration() {
                                statsDescription = "at configuration \(currentConfiguration.id)"
                            }
                            else {
                                statsDescription = "at fixed configuration: \(currentKnobSettings)"
                            }
                            let statsForCurrentKnobSettings = Statistics(measure: m, windowSize: Int(windowSize), description: statsDescription)
                            perKnobSettingsStatsForM[currentKnobSettings] = statsForCurrentKnobSettings
                            statsPerKnobSettings[m] = perKnobSettingsStatsForM
                            statsForCurrentKnobSettings.observe(measure)
                        }
                    }
                    else {
                        FAST.fatalError("Current knob settings not registered in runtime.")
                    }
                }
            }
        }
    }

    public func values() -> [String : Double] {
        return Dictionary(stats.map{ (n,s) in (n, s.lastObservedValue) })
    }

    public func windowAverages() -> [String : Double] {
        return Dictionary(stats.map{ (n,s) in (n, s.windowAverage) })
    }

    func reportProgress() {
        progress += 1
        samplingPolicy.reportProgress(progress)
    }
}
