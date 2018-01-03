import CEnergymon

class CEnergyMonitor : EnergyMonitor {
    var em = energymon()

    /* Get the energymon instance and initialize */
    init() {
        _ = energymon_get_default(&em)
        _ = em.finit(&em)
    }

    /* Returns the current energy in microjoules */
    func readEnergy() -> UInt64 {
        return em.fread(&em)
    }

    /* Destroy the energymon instance */
    deinit {
        _ = em.ffinish(&em)
    }
}
