/**

  An ClockMonitor is used to make time readings from actual or emulated hardware.

*/

public protocol ClockMonitor {
    /* Returns the current value of the time counter */
    func readClock() -> Double
}
