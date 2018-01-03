/**

  An EnergyMonitor is used to make energy readings from actual or emulated hardware.

*/

public protocol EnergyMonitor {
    /* Returns the current energy in microjoules */
    func readEnergy() -> UInt64
}
