/**

  An EnergyMonitor is used to make energy readings from actual or emulated hardware.

*/

import CEnergymon

internal protocol EnergyMonitor {

    /* Returns the current energy in microjoules */
    func read() -> UInt64

}

internal class CEnergyMonitor : EnergyMonitor {

    var em = energymon()

    /* Get the energymon instance and initialize */
    init() {
        let _ = energymon_get_default(&em)
        let _ = em.finit(&em)
    }

    /* Returns the current energy in microjoules */
    func read() -> UInt64 {
        return em.fread(&em)
    }

    /* Destroy the energymon instance */
    deinit {
        let _ = em.ffinish(&em)
    }

}