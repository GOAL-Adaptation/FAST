import Foundation

class DefaultClockMonitor : ClockMonitor {
    init() {}

    /* Returns the current value of the time counter */
    func readClock() -> Double {
        return NSDate().timeIntervalSince1970
    }
}
