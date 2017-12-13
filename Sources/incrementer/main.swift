/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Example application: Incrementer
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import Foundation
import HeliumLogger
import LoggerAPI
import SQLite
import FASTController
import FAST

//---------------------------------------

let applicationName = "incrementer"

//-----------------------------------------------------------------------------------------------
// Knobs
//-----------------------------------------------------------------------------------------------

let threshold = Knob("threshold", 10000000)
let step = Knob("step", 1)

//-----------------------------------------------------------------------------------------------
// Text API access and Emulation
//-----------------------------------------------------------------------------------------------

/** Incrementer Application Knobs */
class IncrementerApplicationKnobs: TextApiModule {

    let name = "applicationKnobs"
    var subModules = [String : TextApiModule]()

    init() {
        self.addSubModule(newModule: threshold)
        self.addSubModule(newModule: step)
    }

}

/** Incrementer Application instance */
class Incrementer: Application, EmulateableApplication {

    let name = applicationName
    var subModules = [String : TextApiModule]()

    var applicationKnobs = IncrementerApplicationKnobs()

    /** Initialize the application */
    required init() {
        Runtime.registerApplication(application: self)
        Runtime.initializeArchitecture(name: "ArmBigLittle")
        Runtime.establishCommuncationChannel()
        self.addSubModule(newModule: applicationKnobs)
    }

    /** Look up the id (in the database) of the current application configuration. */
    func getCurrentConfigurationId(database: Database) -> Int {
        return database.getCurrentConfigurationId(application: self)
    }

}

/** Create that container from above */
var applicationContainer = Incrementer()

//-----------------------------------------------------------------------------------------------
// Implementation
//-----------------------------------------------------------------------------------------------

let window: UInt32 = 20

var x = 0

optimize(applicationName, across: window) {
    let start = NSDate().timeIntervalSince1970
    var operations = 0.0
    while(x < threshold.get()) {
        x += step.get()
        operations += 1
    }
    x = 0
    let latency = NSDate().timeIntervalSince1970 - start
    Runtime.measure("latency", latency)
    Runtime.measure("operations", operations)
}
