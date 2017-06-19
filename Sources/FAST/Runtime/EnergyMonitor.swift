/**

  An EnergyMonitor is used to make energy readings from actual or emulated hardware.

*/

import CEnergymon

public protocol EnergyMonitor {

    /* Returns the current energy in microjoules */
    func readEnergy() -> UInt64
}

class CEnergyMonitor : EnergyMonitor {

    var em = energymon()

    /* Get the energymon instance and initialize */
    init() {
        let _ = energymon_get_default(&em)
        let _ = em.finit(&em)
    }

    /* Returns the current energy in microjoules */
    func readEnergy() -> UInt64 {
        return em.fread(&em)
    }

    /* Destroy the energymon instance */
    deinit {
        let _ = em.ffinish(&em)
    }
}

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