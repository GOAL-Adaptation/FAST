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
import LoggerAPI
@testable import FAST

//---------------------------------------


class DatabaseTests: XCTestCase {

    override func setUp() {
        initializeRandomNumberGenerators()
        recreateTestDatabase()
    }

    let dbFile = "DatabaseTests.db"

    /** Incrementer Application instance */
    class Incrementer: EmulateableApplication {

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
            self.addSubModule(newModule: applicationKnobs)
            self.applicationKnobs.addSubModule(newModule: threshold)
            self.applicationKnobs.addSubModule(newModule: step)
        }

        /** Look up the id (in the database) of the current application configuration. */
        func getCurrentConfigurationId(database: Database) -> Int {
            return database.getCurrentConfigurationId(application: self)
        }

    }

    @discardableResult func recreateTestDatabase() -> Database {

        if !FileManager.default.fileExists(atPath: dbFile) {
            FileManager.default.createFile(atPath: dbFile, contents: nil)
        }
        
        if let loadSchemaQuery = readFile(withName: "Database", ofType: "sql", fromBundle: Bundle(for: type(of: self))),
           let insertDataQuery = readFile(withName: "DatabaseTests", ofType: "sql", fromBundle: Bundle(for: type(of: self))),
           let db = Database(databaseFile: dbFile) {            
            do {
                try db.execute(script: loadSchemaQuery)
                try db.execute(script: insertDataQuery)
                db.database.close()
                Log.info("Test database recreated.")
            }
            catch let error {
                let errorMessage = "Unable to execute test database schema and data files: \(error)."
                Log.error(errorMessage)
                fatalError(errorMessage)
            }
            
            return db

        }
        else {
            let errorMessage = "Unable to load test database schema and data files."
            Log.error(errorMessage)
            fatalError(errorMessage)
        }
    }

    func testGetReferenceApplicationConfigurationID() {
        
        if let database = Database(databaseFile: dbFile) {
            var referenceApplicationConfigurationId = database.getReferenceApplicationConfigurationID(application: "RADAR")
            XCTAssertEqual(6, referenceApplicationConfigurationId)
            referenceApplicationConfigurationId = database.getReferenceApplicationConfigurationID(application: "x264")
            XCTAssertEqual(7, referenceApplicationConfigurationId)
        }
    }

    func testGetReferenceSystemConfigurationID() {       
        if let database = Database(databaseFile: dbFile) {
            var referenceSystemConfigurationId = database.getReferenceSystemConfigurationID(architecture: "ARM-big.LITTLE")
            XCTAssertEqual(1, referenceSystemConfigurationId)
            referenceSystemConfigurationId = database.getReferenceSystemConfigurationID(architecture: "XilinxZcu")
            XCTAssertEqual(2, referenceSystemConfigurationId)
        }
    }


    func testObtainOutliers() {
        if let database = Database(databaseFile: dbFile) {
            var outliers = database.obtainOutliers(application: "RADAR")
            XCTAssertEqual(16, outliers.0)
            XCTAssertEqual(64, outliers.1)
            outliers = database.obtainOutliers(application: "x264")
            XCTAssertEqual(17, outliers.0)
            XCTAssertEqual(65, outliers.1)
        }
    }

    func testGetTapeNoise() {
        if let database = Database(databaseFile: dbFile) {
            var tapeNoise = database.getTapeNoise(application: "RADAR")
            XCTAssertEqual(0.001953125, tapeNoise)
            tapeNoise = database.getTapeNoise(application: "x264")
            XCTAssertEqual(0.001953567, tapeNoise)
        }
    }

    func testGetWarmupInputs() {
        if let database = Database(databaseFile: dbFile) {
            var numberOfInputs = database.getWarmupInputs(application: "RADAR")
            XCTAssertEqual(2, numberOfInputs)
            numberOfInputs = database.getWarmupInputs(application: "x264")
            XCTAssertEqual(1, numberOfInputs)
        }
    }

    func testGetNumberOfInputsProfiled() {
        if let database = Database(databaseFile: dbFile) {
            var numberOfInputs = database.getNumberOfInputsProfiled(application: "RADAR", architecture: "ARM-big.LITTLE", appCfg: 6, appInp: 1, sysCfg: 1)
            XCTAssertEqual(3, numberOfInputs)
            numberOfInputs = database.getNumberOfInputsProfiled(application: "x264", architecture: "ARM-big.LITTLE", appCfg: 7, appInp: 3, sysCfg: 1)
            XCTAssertEqual(2, numberOfInputs)
        }
    }

    func testReadDelta() {
        if let database = Database(databaseFile: dbFile) {
            var time_energy = database.readDelta(application: "RADAR", architecture: "ARM-big.LITTLE", appCfg: 6, appInp: 1, sysCfg: 1, processing: 3 )
            XCTAssertEqual(-1584, time_energy.0)  // DXN_DBG: negative delta time for now
            XCTAssertEqual(664, time_energy.1)
            time_energy = database.readDelta(application: "x264", architecture: "ARM-big.LITTLE", appCfg: 7, appInp: 3, sysCfg: 1, processing: 2 )
            XCTAssertEqual(5654, time_energy.0)
            XCTAssertEqual(4218, time_energy.1)
        }
    }

    func testGetCurrentApplicationConfigurationId() {  
        let incrementerApplication = Incrementer()
        if let database = Database(databaseFile: dbFile) {
            let currentApplicationConfigurationId = database.getCurrentConfigurationId(application: incrementerApplication)
            XCTAssertEqual(13, currentApplicationConfigurationId)
        }
    }

    func testGetCurrentSystemConfigurationId() {  
        let xilinxArchecture = XilinxZcu()
        if let database = Database(databaseFile: dbFile) {
            let currentSystemConfigurationId = database.getCurrentConfigurationId(architecture: xilinxArchecture)
            XCTAssertEqual(2, currentSystemConfigurationId)
        }
    }

    // TODO: more functions to be tested

    static var allTests = [

       ("testGetReferenceSystemConfigurationID", testGetReferenceSystemConfigurationID),
        ("testGetReferenceApplicationConfigurationID", testGetReferenceApplicationConfigurationID),
        ("testObtainOutliers", testObtainOutliers),
        ("testGetTapeNoise", testGetTapeNoise),
       ("testGetWarmupInputs", testGetWarmupInputs),
       ("testGetNumberOfInputsProfiled", testGetNumberOfInputsProfiled),
        ("testReadDelta", testReadDelta),
        ("testGetCurrentSystemConfigurationId", testGetCurrentSystemConfigurationId),
        ("testGetCurrentApplicationConfigurationId", testGetCurrentApplicationConfigurationId)
    ]

}