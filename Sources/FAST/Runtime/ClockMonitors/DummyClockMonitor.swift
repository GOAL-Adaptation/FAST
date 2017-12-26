import Foundation

class DummyClockMonitor : ClockMonitor {
    init() {}

    /* Returns the current value of the time counter */
    func readClock() -> Double {
        return 0.0
    }
}
