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
import PerfectSQLite

//-------------------------------

// Key prefix for initialization
fileprivate let key = ["proteus", "emulator"]

//-------------------------------

enum EmulationDatabaseType {
  case Dict, SQLite
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
      }
      else if emulationDatabaseType == .SQLite,
         let database = SQLiteDatabase() {
        self.database = database
      } else {
        Log.error("Could not initialize the Database.")
        fatalError()
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

    let referenceApplicationConfigurationID = self.database.getReferenceApplicationConfigurationID(application: application.name)
    let referenceSystemConfigurationID      = self.database.getReferenceSystemConfigurationID(architecture: architecture.name)

    var readDeltaTime: Double
    var readDeltaEnergy: Double

    // Data is profiled
    if ((applicationConfigurationID == referenceApplicationConfigurationID) || (systemConfigurationID == referenceSystemConfigurationID)) {

      (readDeltaTime, readDeltaEnergy) = self.database.readDelta(application: application.name, architecture: architecture.name, appCfg: applicationConfigurationID, appInp: applicationInputID, sysCfg: systemConfigurationID, processing: progressCounter)
      
      Log.debug("Emulator readDelta-profiled: for applicationConfigurationID = \(applicationConfigurationID) systemConfigurationID = \(systemConfigurationID) applicationInputStreamID = \(applicationInputID) progressCounter = \(progressCounter) readDeltaTime = \(readDeltaTime) readDeltaEnergy = \(readDeltaEnergy)")
      
      return (readDeltaTime, readDeltaEnergy)

    /* Data is interpolated: Value(appCfg, sysCfg) ~    [ Value(appCfg0, sysCfg)  / Value(appCfg0, sysCfg0) ] *
     *                                                * [ Value(appCfg,  sysCfg0) / Value(appCfg0, sysCfg0) ]
     *                                                *   Value(appCfg0, sysCfg0) =
     *
     *                                                =
     *                                                  [ Value(appCfg0, sysCfg)  / Value(appCfg0, sysCfg0) ] * Value(appCfg, sysCfg0)         */
    } else {

      Log.debug("Emulator readDelta-interpolated: data is interpolated for applicationConfigurationID = \(applicationConfigurationID) systemConfigurationID = \(systemConfigurationID) applicationInputStreamID = \(applicationInputID)")

      var cumulativeDeltaTime: Double   = 0.0
      var cumulativeDeltaEnergy: Double = 0.0

      // Value(appCfg0, sysCfg)
      (readDeltaTime, readDeltaEnergy) = self.database.readDelta(application: application.name, architecture: architecture.name, appCfg: referenceApplicationConfigurationID, appInp: applicationInputID, sysCfg: systemConfigurationID, processing: progressCounter)
      
      Log.debug("Emulator readDelta: get deltas for referenceApplicationConfigurationID = \(referenceApplicationConfigurationID) systemConfigurationID = \(systemConfigurationID) readDeltaTime = \(readDeltaTime) readDeltaEnergy = \(readDeltaEnergy)")

      cumulativeDeltaTime   = readDeltaTime
      cumulativeDeltaEnergy = readDeltaEnergy

      // Value(appCfg0, sysCfg) / Value(appCfg0, sysCfg0)
      (readDeltaTime, readDeltaEnergy) = self.database.readDelta(application: application.name, architecture: architecture.name, appCfg: referenceApplicationConfigurationID, appInp: applicationInputID, sysCfg: referenceSystemConfigurationID, processing: progressCounter)

      Log.debug("Emulator readDelta1: get deltas for referenceApplicationConfigurationID = \(referenceApplicationConfigurationID) referenceSystemConfigurationID = \(referenceSystemConfigurationID) readDeltaTime = \(readDeltaTime) readDeltaEnergy = \(readDeltaEnergy)")

      if readDeltaTime != 0.0 {
        cumulativeDeltaTime   = cumulativeDeltaTime   / readDeltaTime
      }
      else {
        Log.warning("Cannot compute Time(appCfg0, sysCfg) / Time(appCfg0, sysCfg0) since the denominator is 0. Leaving cumulativeDeltaTime unchanged.")
      }

      if readDeltaEnergy != 0.0 {
        cumulativeDeltaEnergy = cumulativeDeltaEnergy / readDeltaEnergy
      }
      else {
        Log.warning("Cannot compute Energy(appCfg0, sysCfg) / Energy(appCfg0, sysCfg0) since the denominator is 0. Leaving cumulativeDeltaEnergy unchanged.")
      }

      // [ Value(appCfg0, sysCfg) / Value(appCfg0, sysCfg0) ] * Value(appCfg, sysCfg0)
      (readDeltaTime, readDeltaEnergy) = self.database.readDelta(application: application.name, architecture: architecture.name, appCfg: applicationConfigurationID, appInp: applicationInputID, sysCfg: referenceSystemConfigurationID, processing: progressCounter)
      
      Log.debug("Emulator readDelta2: get deltas for applicationConfigurationID = \(applicationConfigurationID) referenceSystemConfigurationID = \(referenceSystemConfigurationID) readDeltaTime = \(readDeltaTime) readDeltaEnergy = \(readDeltaEnergy) cumulativeDeltaTime = \(cumulativeDeltaTime) cumulativeDeltaEnergy = \(cumulativeDeltaEnergy)")

      cumulativeDeltaTime   = cumulativeDeltaTime   * readDeltaTime
      cumulativeDeltaEnergy = cumulativeDeltaEnergy * readDeltaEnergy
      
      Log.debug("Emulator readDelta3: interpolated deltas for applicationConfigurationID = \(applicationConfigurationID) systemConfigurationID = \(systemConfigurationID) cumulativeDeltaTime = \(cumulativeDeltaTime) cumulativeDeltaEnergy = \(cumulativeDeltaEnergy)")

      return (cumulativeDeltaTime, cumulativeDeltaEnergy)
    }
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
