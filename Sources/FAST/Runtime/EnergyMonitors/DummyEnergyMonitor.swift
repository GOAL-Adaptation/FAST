class DummyEnergyMonitor : EnergyMonitor {
    /* Get the energymon instance and initialize */
    init() {}

    /* Returns the current energy in microjoules */
    func readEnergy() -> UInt64 {
        return 0
    }

    /* Destroy the energymon instance */
    deinit {}
}
