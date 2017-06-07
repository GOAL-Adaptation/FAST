/**

  A Statistics object is used to compute the cumulative (total) and moving (window) average for a single measure.

*/

import Foundation

/**
    Computes total and window statistics for a single quantity,
    using constant-time algorithms.

    - Cumulative moving average is computed over all observed values.
    - Window average is computed over the N latest observations,
      where N is the windowSize passed to init().
*/
internal class Statistics {

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