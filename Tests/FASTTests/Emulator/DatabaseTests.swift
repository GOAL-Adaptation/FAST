/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Tests of Database
 *
 *  author: Zung Nguyen
 */

//---------------------------------------

import Source
import XCTest
@testable import FAST

//---------------------------------------

class DatabaseTests: XCTestCase {

    /** Incrementer Application instance */
    class Incrementer: Application, EmulateableApplication {

        let name = "incrementer"
        var subModules = [String : TextApiModule]()

        // Knobs 
        let threshold = Knob("threshold", 10000000)
        let step = Knob("step", 1)

        /** Incrementer Application Knobs */
        class IncrementerApplicationKnobs: TextApiModule {

            let name = "applicationKnobs"
            var subModules = [String : TextApiModule]()

        }

        var applicationKnobs = IncrementerApplicationKnobs()

        /** Initialize the application */
        required init() {
            Runtime.registerApplication(application: self)
            Runtime.initializeArchitecture(name: "ArmBigLittle")
            Runtime.establishCommuncationChannel()
            self.addSubModule(newModule: applicationKnobs)
            self.applicationKnobs.addSubModule(newModule: threshold)
            self.applicationKnobs.addSubModule(newModule: step)
        }

        /** Look up the id (in the database) of the current application configuration. */
        func getCurrentConfigurationId(database: Database) -> Int {
            return database.getCurrentConfigurationId(application: self)
        }

    }

    let incrementerApplication = Incrementer()

    let dbFile = "/Users/dxnguyen/Documents/Proteus/FAST/Tests/FASTTests/Emulator/incrementer.db"

    func testGetWarmupInputs() {
        if let database = Database(databaseFile: dbFile) {
            var numberOfInputs = database.getWarmupInputs(application: "RADAR")
            XCTAssertEqual(2, numberOfInputs)
            numberOfInputs = database.getWarmupInputs(application: "x264")
            XCTAssertEqual(1, numberOfInputs)
        }
    }

    // TODO: more functions to be tested

    static var allTests = [
        ("testGetWarmupInputs", testGetWarmupInputs)
    ]

}