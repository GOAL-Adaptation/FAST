/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Test for tracing incrementer.
 *  Generate SQL script to insert fictitious delta time and delta energy into a database.
 *  Execute the generated script to populate a database named TracingTests.db.
 *
 *  author: Zung Nguyen
 */

//---------------------------------------

import Source
import XCTest
import LoggerAPI
@testable import FAST

//---------------------------------------


class TracingTests: FASTTestCase {

    override func setUp() {
        super.setUp()
        initializeRandomNumberGenerators()
        recreateTestDatabase()
    }

    let dbFile = "TracingTests.db"

    /** Incrementer Application instance */
    class Incrementer: EmulateableApplication {

        let name = "incrementer"
        var subModules = [String : TextApiModule]()

        // Knobs
        let threshold: Knob<Int>
        let step: Knob<Int>

        /** Incrementer Application Knobs */
        class IncrementerApplicationKnobs: TextApiModule {

            let name = "applicationKnobs"
            var subModules = [String : TextApiModule]()

        }

        var applicationKnobs = IncrementerApplicationKnobs()

        /** Initialize the application */
        required init(runtime: Runtime) {
            threshold = Knob("threshold", 10000000)
            step = Knob("step", 1)
            runtime.registerApplication(application: self)
            runtime.initializeArchitecture(name: "XilinxZcu")
            self.addSubModule(newModule: applicationKnobs)
            self.applicationKnobs.addSubModule(newModule: threshold)
            self.applicationKnobs.addSubModule(newModule: step)
        }

        /** Look up the id (in the database) of the current application configuration. */
        func getCurrentConfigurationId(database: Database) -> Int {
            return database.getCurrentConfigurationId(application: self)
        }

    }

    func recreateTestDatabase() {

        if !FileManager.default.fileExists(atPath: dbFile) {
            FileManager.default.createFile(atPath: dbFile, contents: nil)
        }

        if let loadSchemaQuery = readFile(withName: "Database", ofType: "sql", fromBundle: Bundle(for: type(of: self))),
           let db = SQLiteDatabase(databaseFile: dbFile) {
            do {
                try db.execute(script: loadSchemaQuery)
                db.database.close()
                Log.info("Test database recreated.")
            }
            catch let error {
                let errorMessage = "Unable to execute test database schema and data files: \(error)."
                Log.error(errorMessage)
                fatalError(errorMessage)
            }
        }
        else {
            let errorMessage = "Unable to load test database schema and data files."
            Log.error(errorMessage)
            fatalError(errorMessage)
        }
    }

    func testEmitScriptForApplicationTracing() {
        let incrementerApplication = Incrementer(runtime: runtime)
        let xilinxArchitecture = XilinxZcu(runtime: runtime)

        let intentKnobs =
        ["threshold": ([2000000,4000000,6000000,8000000,10000000], 10000000),
         "step": ([1,2,3,4], 1),
         "utilizedCores": ([1,2,3,4], 4),
        //  "utilizedCoreFrequency": ([300,400,600,1200], 1200)
        ] as [String : ([Any], Any)]
        let appKnobsInsertion =
        emitScriptForApplicationAndKnobsInsertion(
            application: incrementerApplication,
            warmupInputNum: 0,
            intentKnobList: intentKnobs
        )
        let (currentAppConfigInsertion, currentAppConfigName) =
        emitScriptForCurrentApplicationConfigurationInsertion(
            application: incrementerApplication
        )
        let appInputStreamInsertion =
        emitScriptForApplicationInputStreamInsertion(
            applicationName: incrementerApplication.name,
            inputStreamName: "incrementer input stream 1"
        )
        let appInputStream_appConfigInsertion =
        emitScriptForApplicationInputStream_ApplicationConfigurationInsertion(
            applicationName: incrementerApplication.name,
            inputStreamName: "incrementer input stream 1",
            appConfigName  : currentAppConfigName
        )
        let jobLogParamInsertion =
        emitScriptForJobLogParameterInsertion(
            applicationName: incrementerApplication.name,
            energyOutlier  : 64.3,
            tapeNoise      : 0.00012345,
            timeOutlier    : 18.5
        )

        let sysKnobInsertion =
        emitScriptForSystemAndKnobsInsertion(
            architecture:   xilinxArchitecture,
            intentKnobList: intentKnobs
        )
        let (currentSysConfigInsertion, currentSysConfigName) =
        emitScriptForCurrentSystemConfigurationInsertion(architecture: xilinxArchitecture)

        let tracingScript =
            "BEGIN; "
            + appKnobsInsertion
            + currentAppConfigInsertion
            + jobLogParamInsertion
            + appInputStreamInsertion
            + sysKnobInsertion
            + currentSysConfigInsertion
            + appInputStream_appConfigInsertion
            + "COMMIT;"
            + "BEGIN;"
            + emitScriptForDeltaTimeDeltaEnergyInsertion(
                applicationName: incrementerApplication.name,
                inputStreamName: "incrementer input stream 1",
                appConfigName  : currentAppConfigName,
                sysConfigName  : currentSysConfigName,
                inputNumber    : 1,
                deltaTime      : 12345,
                deltaEnergy    : 67890
            )
            + emitScriptForDeltaTimeDeltaEnergyInsertion(
                applicationName: incrementerApplication.name,
                inputStreamName: "incrementer input stream 1",
                appConfigName  : currentAppConfigName,
                sysConfigName  : currentSysConfigName,
                inputNumber    : 2,
                deltaTime      : 54321,
                deltaEnergy    : 98760
            )
            + "COMMIT;"


        if let db = SQLiteDatabase(databaseFile: dbFile) {
            do {
                try db.execute(script: tracingScript)
                db.database.close()
            }
            catch let error {
                let errorMessage = "Unable to execute script >>> \(tracingScript)  <<<: \(error)."
                Log.error(errorMessage)
                fatalError(errorMessage)
            }
        }

    }

    static var allTests = [
        ("testEmitScriptForApplicationTracing", testEmitScriptForApplicationTracing)
    ]

}
