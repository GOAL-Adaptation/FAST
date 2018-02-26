/**

  A Statistics object is used to compute the cumulative (total) and moving (window) average for a single measure.

*/

import Foundation
import LoggerAPI

/**
    Computes total and window statistics for a single quantity,
    using constant-time algorithms.

    - Cumulative average and variance is computed over all observed values.

    - Window average are computed over the N latest observations, 
      where N is the windowSize passed to init()

*/
internal class Statistics {

    private var measure: String

    /* Total statistics */
    private var _totalAverage: Double = 0
    private var totalCount: Int = 0
    private var deviations: Double = 0 // Used for Welford incremental variance (TAOCP, vol 2, ed 3, p 232)

    /* Window statistics */
    private var _windowAverage: Double = 0
    private var window: [Double] = []
    private var windowHead: Int = 0
    private var windowIsComplete: Bool = false
    private var windowLock: NSLock = NSLock()

    /** Cumulative average, computed over all observations.
     *  Note: Undefined (Double.nan) when the number of observations is less than 2. */
    var totalAverage: Double {
        get { 
            if totalCount < 2 {
                return Double.nan
            }
            else {
                return _totalAverage
            }
        }
    }

    /** Cumulative variance, computed over all observations. 
     *  Note: Undefined (Double.nan) when the number of observations is less than 2. */
    var totalVariance: Double {
        get { 
            if totalCount < 2 {
                return Double.nan
            }
            else {
                return deviations / Double(totalCount - 1) 
            }
        }
    }

    /** Window average, computed over the past windowSize observations. */
    var windowAverage: Double {
        get { return _windowAverage }
    }

    init(measure: String, windowSize: Int) {
        self.measure = measure
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
        /* Total mean/variance statistics, incremental algorithm by Welford (TAOCP, vol 2, ed 3, p 232) */
        totalCount += 1
        let delta = value - _totalAverage
        _totalAverage += delta / Double(totalCount)
        let delta2 = value - _totalAverage
        deviations += delta * delta2
        /* Window statistics */
        synchronized(windowLock) {
            /* Window average */
            if windowIsComplete {
                _windowAverage = _windowAverage + (value - window[windowHead]) / Double(windowSize)
            }
            else {
                _windowAverage = _totalAverage
                if windowHead == windowSize - 1 {
                    windowIsComplete = true
                }
            }
            window[windowHead] = value
            windowHead = (windowHead + 1) % windowSize
        }
        Log.verbose("Statistics for \(measure). Total average: \(totalAverage), total variance: \(totalVariance), window average: \(windowAverage).")
        return value
    }

}