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

class Incrementer: Application, EmulateableApplication {
    class ApplicationKnobs: TextApiModule {
        let name = "applicationKnobs"
        var subModules = [String : TextApiModule]()

        init(submodules: [TextApiModule]) {
            for module in submodules {
              self.addSubModule(newModule: module)
            }
        }
    }

    let name = "incrementer"
    var subModules = [String : TextApiModule]()

    var applicationKnobs: ApplicationKnobs // = ApplicationKnobs()

    let threshold: Knob<Int>
    let step: Knob<Int>

    /** Initialize the application */
    required init() {
        initRuntime()
        threshold = Knob("threshold", 10000000)
        step = Knob("step", 1)
        applicationKnobs = ApplicationKnobs(submodules: [threshold, step])

        Runtime.registerApplication(application: self)
        Runtime.initializeArchitecture(name: "XilinxZcu")
        Runtime.establishCommuncationChannel()
        self.addSubModule(newModule: applicationKnobs)
    }

    /** Look up the id (in the database) of the current application configuration. */
    func getCurrentConfigurationId(database: Database) -> Int {
        return database.getCurrentConfigurationId(application: self)
    }
}

let app = Incrementer()

let window: UInt32 = 20

var x = 0

optimize(app.name, across: window) {
    let start = NSDate().timeIntervalSince1970
    var operations = 0.0
    while(x < app.threshold.get()) {
        x += app.step.get()
        operations += 1
    }
    x = 0
    let latency = NSDate().timeIntervalSince1970 - start
    Runtime.measure("latency", latency)
    Runtime.measure("operations", operations)
}
