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
import LoggerAPI

//-------------------------------

// Key prefix for initialization
fileprivate let key = ["proteus", "emulator"]

//-------------------------------

enum EmulationDatabaseType {
  case Dict
}

/** Emulator */
class Emulator: TextApiModule, ClockMonitor, EnergyMonitor {

  var subModules = [String : TextApiModule]()

  let name = "Emulator"

  // Database containing the profiled data
  var database: Database

  // Emulation Identifiers
  var application: EmulateableApplication
  var applicationInputId: Int
  var architecture: EmulateableArchitecture

  // Global Counters
  var numberOfProcessedInputs: UInt64
  var globalEnergy: UInt64
  var globalTime: Double

  private unowned let runtime: Runtime

  // ClockMonitor Interface
  func readClock() -> Double {
    updateGlobalCounters()
    Log.debug("Emulator.readClock = \(globalTime) ")
    return self.globalTime
  }

  // EnergyMonitor Interface
  func readEnergy() -> UInt64 {
      updateGlobalCounters()
      return self.globalEnergy
  }

  // Initialization
  required init(application: EmulateableApplication, applicationInput: Int, architecture: EmulateableArchitecture, runtime: Runtime) {
      self.runtime = runtime

      let emulationDatabaseType = initialize(type: EmulationDatabaseType.self, name: "emulationDatabaseType", from: key, or: .Dict)

      if emulationDatabaseType == .Dict,
         let database = DictDatabase() {
        self.database = database
      } else {
        FAST.fatalError("Could not initialize the Database.")
      }
      self.application = application
      self.applicationInputId = applicationInput
      self.architecture = architecture
      self.numberOfProcessedInputs = 0
      self.globalEnergy = 0
      self.globalTime = 0.0

      self.addSubModule(newModule: database)
  }

  // Deinit
  deinit {

  }

  //-------------------------------

  /** Interpolate System Measurements */
  func readDelta(appCfg applicationConfigurationID: Int,
                 appInp applicationInputID: Int,  // ID of application inputstream
                 sysCfg systemConfigurationID: Int,
                 processing progressCounter: Int)
                    ->
                 (Double, Double) {

    Log.debug("Emulator readDelta: get deltaTime and deltaEnergy from the emulation database.")

    let (readDeltaTime, readDeltaEnergy) = self.database.readDelta(application: application.name, architecture: architecture.name, appCfg: applicationConfigurationID, appInp: applicationInputID, sysCfg: systemConfigurationID, processing: progressCounter)
    
    Log.debug("Emulator readDelta: for applicationConfigurationID = \(applicationConfigurationID) systemConfigurationID = \(systemConfigurationID) applicationInputStreamID = \(applicationInputID) progressCounter = \(progressCounter) readDeltaTime = \(readDeltaTime) readDeltaEnergy = \(readDeltaEnergy)")
    
    return (readDeltaTime, readDeltaEnergy)

  }

  //-------------------------------

  /** Update the Global Counters */
  func updateGlobalCounters() {

    // Obtain the current progress of the application
    if let recentNumberOfProcessedInpts = runtime.getMeasure("iteration") {

      // Obtain the Application State
      let applicationConfigurationId   = self.application.getCurrentConfigurationId(database: self.database)

      // Obtain the System State
      let systemConfigurationId        = self.architecture.getCurrentConfigurationId(database: self.database)

      // Emulate system measures for each unemulated input
      if self.numberOfProcessedInputs < UInt64(recentNumberOfProcessedInpts) {

        // The number of unemulated inputs is |(self.numberOfProcessedInputs + 1) ... recentNumberOfProcessedInpts|. Now emulate them.
        var i = self.numberOfProcessedInputs + 1
        while i <= UInt64(recentNumberOfProcessedInpts) {

          // Read Deltas based on Interpolation from profiled data in the Database
          Log.debug("Emulator updateGlobalCounters: call internal func readDelta() to get deltaTime and deltaEnegy.")

          let (deltaTime, deltaEnergy) = readDelta(appCfg: applicationConfigurationId, appInp: self.applicationInputId, sysCfg: systemConfigurationId, processing: Int(i))

          // Increase the Global Counters
          self.globalTime   += deltaTime
          self.globalEnergy += UInt64(deltaEnergy)
          
          i += 1
        }

        // Update the Counter of Processed Inputs
        self.numberOfProcessedInputs = UInt64(recentNumberOfProcessedInpts)
      }
    }
  }
}

//-------------------------------
