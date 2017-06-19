/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Default Architecture
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//---------------------------------------

/** Default Architecture */
class DefaultArchitecture: ClockAndEnergyArchitecture {

    let name = "Default"

    // Default System Measures
    let clockMonitor:  ClockMonitor  = DefaultClockMonitor()
    let energyMonitor: EnergyMonitor = CEnergyMonitor()

    // Initialization registers the system measures
    init() {
        self.registerSystemMeasures()
    }
}

//-----------------
