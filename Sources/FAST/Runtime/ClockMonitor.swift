/**

  An ClockMonitor is used to make time readings from actual or emulated hardware.

*/

import Foundation

public protocol ClockMonitor {

    /* Returns the current value of the time counter */
    func readClock() -> Double

}

class DefaultClockMonitor : ClockMonitor {

    init() {}

    /* Returns the current value of the time counter */
    func readClock() -> Double {
        return NSDate().timeIntervalSince1970
    }

}

class DummyClockMonitor : ClockMonitor {

    init() {}

    /* Returns the current value of the time counter */
    func readClock() -> Double {
        return 0.0
    }

}