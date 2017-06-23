/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *  pemu: Database driven emulator
 *
 *        Emulator Main File
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//-------------------------------

import Foundation
import SQLite

//-------------------------------

// Environment prefix for initialization
fileprivate let environmentPrefix = "proteus_pemu_emulator_"

//-------------------------------

/** Emulator */
class Emulator: TextApiModule, ClockMonitor, EnergyMonitor {

  var subModules = [String : TextApiModule]()

  let name = "Emulator"

  // Database containing the profiled data
  var database = Database()

  // Emulation Identifiers
  var application: EmulateableApplication
  var applicationInputId: Int
  var architecture: EmulateableArchitecture

  // Global Counters
  var numberOfProcessedInputs: UInt64
  var globalEnergy: UInt64
  var globalTime: UInt64

  // ClockMonitor Interface
  func readClock() -> Double {
    updateGlobalCounters()
    return Double(self.globalTime)
  }

  // EnergyMonitor Interface
  func readEnergy() -> UInt64 {
      updateGlobalCounters()
      return self.globalEnergy
  }
  
  // Initialization
  required init(application: EmulateableApplication, applicationInput: Int, architecture: EmulateableArchitecture) {
      self.application = application
      self.applicationInputId = applicationInput
      self.architecture = architecture
      self.numberOfProcessedInputs = 0
      self.globalEnergy = 0
      self.globalTime = 0

      self.addSubModule(moduleName: "database", newModule: database!)
  }

  // Deinit
  deinit {

  }

  //-------------------------------

  /** Interpolate System Measurements */
  func readDelta(appCfg applicationConfigurationID: Int, 
                 appInp applicationInputID: Int, 
                 sysCfg systemConfigurationID: Int, 
                 processing progressCounter: Int) 
                    ->
                 (UInt64, UInt64) {

    let referenceApplicationConfigurationID = self.database!.getReferenceApplicationConfigurationID(application: application.name)
    let referenceSystemConfigurationID      = self.database!.getReferenceSystemConfigurationID(architecture: architecture.name)

    var readDeltaTime: Int 
    var readDeltaEnergy: Int 

    // Data is profiled
    if ((applicationConfigurationID == referenceApplicationConfigurationID) || (systemConfigurationID == referenceSystemConfigurationID)) {

      (readDeltaTime, readDeltaEnergy) = self.database!.readDelta(application: application.name, architecture: architecture.name, appCfg: applicationConfigurationID, appInp: applicationInputID, sysCfg: systemConfigurationID, processing: progressCounter)

      // Convert to UInt64
      return (UInt64(readDeltaTime), UInt64(readDeltaEnergy))

    /* Data is interpolated: Value(appCfg, sysCfg) ~    [ Value(appCfg0, sysCfg)  / Value(appCfg0, sysCfg0) ] *
     *                                                * [ Value(appCfg,  sysCfg0) / Value(appCfg0, sysCfg0) ]
     *                                                *   Value(appCfg0, sysCfg0) =
     *
     *                                                =
     *                                                  [ Value(appCfg0, sysCfg)  / Value(appCfg0, sysCfg0) ] * Value(appCfg, sysCfg0)         */
    } else {

      var cumulativeDeltaTime: Double   = 0.0
      var cumulativeDeltaEnergy: Double = 0.0

      // Value(appCfg0, sysCfg)
      (readDeltaTime, readDeltaEnergy) = self.database!.readDelta(application: application.name, architecture: architecture.name, appCfg: referenceApplicationConfigurationID, appInp: applicationInputID, sysCfg: systemConfigurationID, processing: progressCounter)
      cumulativeDeltaTime   = Double(readDeltaTime)
      cumulativeDeltaEnergy = Double(readDeltaEnergy)

      // Value(appCfg0, sysCfg) / Value(appCfg0, sysCfg0)
      (readDeltaTime, readDeltaEnergy) = self.database!.readDelta(application: application.name, architecture: architecture.name, appCfg: referenceApplicationConfigurationID, appInp: applicationInputID, sysCfg: referenceSystemConfigurationID, processing: progressCounter)
      cumulativeDeltaTime   = cumulativeDeltaTime   / Double(readDeltaTime)
      cumulativeDeltaEnergy = cumulativeDeltaEnergy / Double(readDeltaEnergy)

      // [ Value(appCfg0, sysCfg) / Value(appCfg0, sysCfg0) ] * Value(appCfg, sysCfg0)
      (readDeltaTime, readDeltaEnergy) = self.database!.readDelta(application: application.name, architecture: architecture.name, appCfg: applicationConfigurationID, appInp: applicationInputID, sysCfg: referenceSystemConfigurationID, processing: progressCounter)
      cumulativeDeltaTime   = cumulativeDeltaTime   * Double(readDeltaTime)
      cumulativeDeltaEnergy = cumulativeDeltaEnergy * Double(readDeltaEnergy)

      // Convert to UInt64
      return (UInt64(cumulativeDeltaTime), UInt64(cumulativeDeltaEnergy))
    }
  }

  //-------------------------------

  /** Update the Global Counters */
  func updateGlobalCounters() {

    // Obtain the current progress of the application
    if let recentNumberOfProcessedInpts = Runtime.readMeasure("iteration") {

      // Obtain the Application State
      let applicationConfigurationId   = self.application.getConfigurationId(database: self.database!)

      // Obtain the System State
      let systemConfigurationId        = self.architecture.getConfigurationId(database: self.database!)

      // Emulate system measures for each unemulated input
      if self.numberOfProcessedInputs < UInt64(recentNumberOfProcessedInpts) {
        
        let unemulatedInputs = (self.numberOfProcessedInputs + 1) ... UInt64(recentNumberOfProcessedInpts)
        
        for i in unemulatedInputs {

          // Read Deltas based on Interpolation from profiled data in the Database
          let (deltaTime, deltaEnergy) = readDelta(appCfg: applicationConfigurationId, appInp: self.applicationInputId, sysCfg: systemConfigurationId, processing: Int(i)) 
          
          // Increase the Global Counters
          self.globalTime   += deltaTime
          self.globalEnergy += deltaEnergy
        }

        // Update the Counter of Processed Inputs
        self.numberOfProcessedInputs = UInt64(recentNumberOfProcessedInpts)
      }
    }
  }
}

//-------------------------------
