/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Dummy Architecture
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//---------------------------------------

/** Dummy Architecture */
class DummyArchitecture: ClockAndEnergyArchitecture {

    let name = "Dummy"

    // Dummy System Measures
    let clockMonitor:  ClockMonitor  = DummyClockMonitor()
    let energyMonitor: EnergyMonitor = DummyEnergyMonitor()

    // Initialization registers the system measures
    init(runtime: __Runtime) {
        self.registerSystemMeasures(runtime: runtime)
    }
}

//-----------------
