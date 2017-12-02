/**
* Generating SQL scripts to trace the profiling of an application and to insert profiling data
* into appropriate tables in the emulation database.  The following describes how to use these
* scripts when profiling a CP.
*
* Step 0: The schema for the emulation database is defined in the script called Database.sql
* located in FAST/Sources/FAST/Emulator.  This script should be run first to create 
* an empty database with all the tables required for emulating a CP.
* 
* Step 1:  Emit SQL to insert application and architecture properties based on an intent
* specification.

  let applicationAndArchictectureInsertion =
    emitScriptForApplicationAndArchitectureInsertion(
          application   : a CP
        , warmupInputNum: a warmup input number for the CP
        , architecture  : an architecture such as XilinxZcu
        , intent        : an intent specification
    )
* 
* Step 2.1: Emit SQL to insert application input stream and job log parameters (if any).

  let appInputStreamInsertion =
    emitScriptForApplicationInputStreamInsertion(
        applicationName: name of CP in step 1,
        inputStreamName: name of input stream for the CP
    )
*
* Step 2.2: Emit SQL to insert job log parameters (if any).

  let jobLogParamInsertion =
    emitScriptForJobLogParameterInsertion(
        applicationName: name of CP in step 1,
        energyOutlier  : some number,
        tapeNoise      : some number,
        timeOutlier    : some number
    )

* Step 3.1: Emit SQL to insert current application configuration and return the name of
* the current application configuration to be used in subsequent steps.

  let (currentAppConfigInsertion, currentAppConfigName) = 
    emitScriptForCurrentApplicationConfigurationInsertion(
        application: the CP in step 1
    )
*
* Step 3.2: Emit SQL to relate the application input stream in step 2.1 and the application
* configuration in step 3.1.

  let appInputStream_appConfigInsertion =
    emitScriptForApplicationInputStream_ApplicationConfigurationInsertion(
        applicationName: name of CP in step 1,
        inputStreamName: name of input stream in step 2.1,
        appConfigName  : currentAppConfigName from step 3.1        
    )
*
* Step 4: Emit SQL to insert current system configuration and return the name of
* the current system configuration to be used in subsequent steps.

let (currentSysConfigInsertion, currentSysConfigName) = 
    emitScriptForCurrentSystemConfigurationInsertion(architecture: architecture in step 1)

* Step 5: Run the CP with the given input stream, the current application configuration and
* current system configuration, and emit the SQL script to insert the measured delta time,
* delta energy for each input unit in the input stream.

let deltaTimeDeltaEnergyInsertion = ""
for each input n in input stream {
    obtain delta time and delta energy
    deltaTimeDeltaEnergyInsertion +=
    emitScriptForDeltaTimeDeltaEnergyInsertion(
        applicationName: name of the CP in step ,
        inputStreamName: name of input stream in step 2.1,
        appConfigName  : currentAppConfigName in step 3.1,
        sysConfigName  : currentSysConfigName in step 4,
        inputNumber    : n,
        deltaTime      : the measured delta time,
        deltaEnergy    : the measured delta energy            
    )
}
* 
* The resulting script to insert profiling data of a CP is the concatenation of the scripts
* emmitted in steps 1, 2.1, 2.2, 3.1, 3.2, 4, and 5.  More specifically:
* 
"PRAGMA foreign_keys = 'off'; BEGIN;"
+ applicationAndArchictectureInsertion  // step 1
+ appInputStreamInsertion               // step 2.1
+ jobLogParamInsertion                  // step 2.2 if needed
+ currentAppConfigInsertion             // step 3.1
+ appInputStream_appConfigInsertion     // step 3.2
+ currentSysConfigInsertion             // step 4
+ deltaTimeDeltaEnergyInsertion         // step 5
+ "COMMIT; PRAGMA foreign_keys = 'on';"
*
* author: Dung Nguyen
*/


import Foundation
import LoggerAPI
import SQLite
import SQLite3

    func getReferenceValueType(referenceValue: Any) -> String {
        switch referenceValue {
        case is Int:
            return "INTEGER"
        case is Double:
            return "DOUBLE"
        default:
            fatalError("Unknown knob type")
        }        
    }

    ////// Insertion SQL for appliation related tables  \\\\\\\

    /** Given an application, its warmup input number and a knob list from the intent specfication,
    * make a SQL script to insert the application name, its knobs and their corresponding 
    * reference values into the emulation database.
    * When this script is executed, the application name, its warmup input number, its knob names, 
    * their corresppnding knob types and reference values are entered into the  Application, Knob, 
    * and Application_Knob of the emulation database.
    */
    func emitScriptForApplicationAndKnobsInsertion(
        application   :    EmulateableApplication
        , warmupInputNum: Int
        , intentKnobList: [String : ([Any], Any)]
    ) -> String {
        
        // SQL to insert application name and warmup input number:
        var sqlScript =
        "INSERT OR IGNORE INTO Application(name, warmupInputNum) VALUES('\(application.name)', \(warmupInputNum)); "

        // SQL to insert application knobs and their reference values into the Application_Knob table:
        let appKnobs = application.getStatus()!["applicationKnobs"] as! [String : Any]
        for (appKnobName, _) in appKnobs {            
            for (knobName, rangeReferencePair) in intentKnobList {
                if (appKnobName == knobName) {
                    let referenceValueType = getReferenceValueType(referenceValue: rangeReferencePair.1)
                    sqlScript += 
                        "INSERT OR IGNORE INTO Knob(name) VALUES('\(knobName)'); " +
                        "INSERT OR IGNORE INTO Application_Knob(applicationId, knobId, knobType, knobReferenceValue) " +
                        "VALUES( " +
                        "  (SELECT id FROM Application WHERE name = '\(application.name)'), " +
                        "  (SELECT id FROM Knob WHERE name = '\(knobName)'), " +
                        "  '\(referenceValueType)', " +
                        "  '\(rangeReferencePair.1)'" +
                        ");" 
                }
            }

        }
        return sqlScript
    }

    /** Given an application, its warmup input number and an intent specfication,
    * make a SQL script to insert the application name, its warmup input number, its knobs 
    * and their corresponding reference values into the emulation database.
    * When this script is executed, the application name, its warmup input number, its knob names, 
    * their corresppnding knob types and reference values are entered into the  Application, Knob, 
    * and Application_Knob of the emulation database.
    */
    func emitScriptForApplicationAndKnobsInsertion(
          application   :    EmulateableApplication
        , warmupInputNum: Int
        , intent        : IntentSpec
    ) -> String {
        return emitScriptForApplicationAndKnobsInsertion(
            application: application,
            warmupInputNum: warmupInputNum,
            intentKnobList: intent.knobs
        )
    }

    /** Given an application whose name exists in the emulation database, make a SQL script 
    * to insert its current application configuration in the emulation database.
    * Return the script together with the name of the application configuration.
    * When this script is executed:
    * - a unique application configuration name is inserted into the ApplicationConfiguration table
    * - if the knob names and their value types do not exist in the database, they are inserted into
    * the Knob table and the Application_Knob table
    * _ all the relevant knob names and their corresponding values are inserted into the 
    * ApplicationConfiguration_Application_Knob table
    */
    func emitScriptForCurrentApplicationConfigurationInsertion(application: EmulateableApplication) 
    -> 
    ( 
          String  // script for insertion
        , String  // name of current application configuration
    ) {
        // Build the application configuration name corresponding to the current application configuration:
        var appConfigName = application.name 
        let appKnobs = application.getStatus()!["applicationKnobs"] as! [String : Any]
        for (knobName, knobValueAny) in appKnobs {
            if let knobValueDict = knobValueAny as? [String : Any], let knobValue = knobValueDict["value"] {
                appConfigName += "_\(knobName):\(knobValue)"
            }
        }

        // SQL to insert the application configuration name into the database:
        var sqlScript = 
        "INSERT OR IGNORE INTO ApplicationConfiguration(description) VALUES('\(appConfigName)'); " 

        // SQL to insert the knob values of the current application configuration:
        for (knobName, knobValueAny) in appKnobs {
            if let knobValueDict = knobValueAny as? [String : Any], let knobValue = knobValueDict["value"] {
                sqlScript += 
                // Insert the knob name and its reference value type, in case they are not listed in the intent specification
                "INSERT OR IGNORE INTO Knob(name) VALUES('\(knobName)'); " + 
                "INSERT OR IGNORE INTO Application_Knob(applicationId, knobId, knobType) " +
                "VALUES( " +
                "  (SELECT id FROM Application WHERE name = '\(application.name)'), " +
                "  (SELECT id FROM Knob WHERE name = '\(knobName)'), " +
                "  '\(getReferenceValueType(referenceValue: knobValue))'" +
                "); " +
                // Insert the knob name and its value for this particular application configuration 
                // into the ApplicationConfiguration_Application_Knob table
                "INSERT OR IGNORE INTO ApplicationConfiguration_Application_Knob(applicationConfigurationId, applicationKnobId, knobValue) " +
                "VALUES(" +
                "  (SELECT id FROM ApplicationConfiguration WHERE description = '\(appConfigName)')," + 
                "  (SELECT id FROM Application_Knob WHERE  knobId = (SELECT id FROM Knob WHERE name = '\(knobName)'))," +
                "  '\(knobValue)'" +
                ");"
            }
        }
        return (sqlScript, appConfigName)
    }

    /** Make SQL script to insert input stream name for a given application into the 
    * Application_InputStream table of the emulation table.
    */
    func emitScriptForApplicationInputStreamInsertion( 
          applicationName:  String
        , inputStreamName:  String
    ) -> String {

        let sqlScript =
          "INSERT OR IGNORE INTO ApplicationInputStream(name, applicationId) " + 
          "VALUES(" +
          "'\(inputStreamName)', " +
          "(SELECT id FROM Application WHERE name = '\(applicationName)'));"
        return sqlScript
    }

    /** Given an application name, a corresponding input stream name, and a corresponding application
    * configuration name, find the corresponding applicationConfigurationId and the corresponding
    * applicationInputId and insert them into the ApplicationInputStream_ApplicationConfiguration
    * table of the emulation database.
    */
    func emitScriptForApplicationInputStream_ApplicationConfigurationInsertion( 
          applicationName: String
        , inputStreamName: String
        , appConfigName  : String
    ) -> String {

        let sqlScript =
          "INSERT OR IGNORE INTO ApplicationInputStream_ApplicationConfiguration(applicationConfigurationId, applicationInputId) " + 
          "VALUES(" +
          "(SELECT id FROM ApplicationConfiguration WHERE description = '\(appConfigName)'), " +
          "(SELECT id FROM ApplicationInputStream " +
          "   WHERE name = '\(inputStreamName)' " +
          "   AND   applicationId = (SELECT id FROM Application WHERE name = '\(applicationName)')) " +
          ");"
        return sqlScript
    }

    /** Make SQL script to insert data into the JobLogParameter table of the emulation database.
    */
    func emitScriptForJobLogParameterInsertion(
          applicationName: String
        , energyOutlier  : Double
        , tapeNoise      : Double
        , timeOutlier    : Double
    ) -> String {

        let sqlScript =
          "INSERT OR IGNORE INTO JobLogParameter(applicationId, energyOutlier, tapeNoise, timeOutlier) " + 
          "VALUES(" +
          " (SELECT id FROM Application WHERE name = '\(applicationName)'), " +
          " \(energyOutlier), " +
          " \(tapeNoise), " +
          " \(timeOutlier) " +
          ");"
        return sqlScript        
    }


    /////// Insertion SQL for system (i.e. architecture) related tables \\\\\\\

   /** Given an architecture and a knob list from the intent specfication,
    * make a SQL script to insert the system name, its knobs and their corresponding 
    * reference values into the emulation database.
    * When this script is executed, the system name, its knob names and their corresppnding
    * knob types and reference values are entered into the System, Knob, and System_Knob
    * tables of theemulation database.
    */
    func emitScriptForSystemAndKnobsInsertion( 
          architecture:   EmulateableArchitecture
        , intentKnobList: [String : ([Any], Any)]
    ) -> String {
        
        // SQL to insert application name and warmup input number:
        var sqlScript =
          "INSERT OR IGNORE INTO System(name) VALUES('\(architecture.name)');"

        // SQL to insert application knobs and their reference values into the System_Knob table:
        let sysKnobs =  architecture.getStatus()!["systemConfigurationKnobs"] as! [String : Any]
        for (sysKnobName, _) in sysKnobs {            
            for (knobName, rangeReferencePair) in intentKnobList {
                if (sysKnobName == knobName) {
                    // get the type of the reference value:
                    let referenceValueType = getReferenceValueType(referenceValue: rangeReferencePair.1)
                    sqlScript += 
                    "INSERT OR IGNORE INTO Knob(name) VALUES('\(knobName)'); " +
                    "INSERT OR IGNORE INTO System_Knob(systemId, knobId, knobType, knobReferenceValue) " +
                    "VALUES( " +
                    "  (SELECT id FROM System WHERE name = '\(architecture.name)'), " +
                    "  (SELECT id FROM Knob WHERE name = '\(knobName)'), " +
                    "  '\(referenceValueType)', " +
                    "  '\(rangeReferencePair.1)'" +
                    ");" 
                }
            }

        }
        return sqlScript
    }

   /** Given an architecture and an intent specfication, make a SQL script to insert the system name,
    * the system knobs listed in the intent and their corresponding  reference values into the emulation database.
    * When this script is executed, the system name, its knob names and their corresppnding
    * knob types and reference values are entered into the System, Knob, and System_Knob
    * tables of the emulation database.
    */
    func emitScriptForSystemAndKnobsInsertion( 
          architecture:   EmulateableArchitecture
        , intent: IntentSpec
    ) -> String {
        return emitScriptForSystemAndKnobsInsertion(
              architecture  : architecture
            , intentKnobList: intent.knobs
        )
    }


    /** Given an architecture whose name exists in the emulation database, make a SQL script 
    * to insert its current system configuration in the emulation database.
    * Return the script together with the name of the system configuration.
    * When this script is executed:
    * - a unique system configuration name is inserted into the SystemConfiguration table
    * - if the knob names and their value types do not exist in the database, they are inserted into
    * the Knob table and the System_Knob table
    * _ all the relevant knob names and their corresponding values are inserted into the 
    * SystemConfiguration_System_Knob table
    */
    func emitScriptForCurrentSystemConfigurationInsertion(architecture: EmulateableArchitecture) 
    -> 
    (
          String   // script for insertion
        , String  // name of current system configuration
    ) {
        // Build the system configuration name corresponding to the current system configuration:
        var sysConfigName = architecture.name 
        let sysKnobs = architecture.getStatus()!["systemConfigurationKnobs"] as! [String : Any]
        for (knobName, knobValueAny) in sysKnobs {
            if let knobValueDict = knobValueAny as? [String : Any], let knobValue = knobValueDict["value"] {
                sysConfigName += "_\(knobName):\(knobValue)"
            }
        }

        // SQL to insert the system configuration name into the database:
        var sqlScript = 
        "INSERT OR IGNORE INTO SystemConfiguration(description) VALUES('\(sysConfigName)'); " 

        // SQL to insert the knob values of the current system configuration:
        for (knobName, knobValueAny) in sysKnobs {
            if let knobValueDict = knobValueAny as? [String : Any], let knobValue = knobValueDict["value"] {
                sqlScript += 
                // Insert the knob name and its reference value type, in case they are not listed in the intent specification
                "INSERT OR IGNORE INTO Knob(name) VALUES('\(knobName)'); " + 
                "INSERT OR IGNORE INTO System_Knob(systemId, knobId, knobType) " +
                "VALUES( " +
                "  (SELECT id FROM System WHERE name = '\(architecture.name)'), " +
                "  (SELECT id FROM Knob WHERE name = '\(knobName)'), " +
                "  '\(getReferenceValueType(referenceValue: knobValue))'" +
                "); " +
                // Insert the knob name and its value for this particular system configuration 
                // into the SystemConfiguration_System_Knob table
                "INSERT OR IGNORE INTO SystemConfiguration_System_Knob(systemConfigurationId, systemKnobId, knobValue) " +
                "VALUES(" +
                "  (SELECT id FROM SystemConfiguration WHERE description = '\(sysConfigName)')," + 
                "  (SELECT id FROM System_Knob WHERE  knobId = (SELECT id FROM Knob WHERE name = '\(knobName)'))," +
                "  '\(knobValue)'" +
                ");"
            }
        }
        return (sqlScript, sysConfigName)
    }

/** Insert delta energy and delta time for a given input number, a given application, 
* a given application input stream, a given application configuration, and a given 
* system configuration into the ApplicationSystemInputLog table fo the emulation database.
*/
func emitScriptForDeltaTimeDeltaEnergyInsertion(
      applicationName: String
    , inputStreamName: String
    , appConfigName  : String
    , sysConfigName  : String
    , inputNumber    : Int
    , deltaTime      : Int
    , deltaEnergy    : Int
) -> String {

    let sqlScript =
    "INSERT OR IGNORE INTO ApplicationSystemInputLog(applicationInputStream_applicationConfigurationId, systemConfigurationId, inputNumber, deltaTime, deltaEnergy) " +
    "VALUES(" +
    "  (SELECT id FROM ApplicationInputStream_ApplicationConfiguration " +
    "      WHERE applicationConfigurationId = (SELECT id FROM ApplicationConfiguration WHERE description = '\(appConfigName)') " +
    "      AND applicationInputId = (SELECT id FROM ApplicationInputStream " +
    "                                  WHERE name = '\(inputStreamName)' " +
    "                                  AND   applicationId = (SELECT id FROM Application WHERE name = '\(applicationName)'))), " + 
    "  (SELECT id FROM SystemConfiguration WHERE description = '\(sysConfigName)'), " +
    "  \(inputNumber), " +
    "  \(deltaTime), " +
    "  \(deltaEnergy)" + 
    ");"
    return sqlScript
}

/** Make SQL script to insert application and architecture properties into the 
* Application table, Knob table, System table, Application_Knob table, and 
* System_Knob table of the emulation database.
*/
func emitScriptForApplicationAndArchitectureInsertion(
      application   :    EmulateableApplication
    , warmupInputNum: Int
    , architecture  :   EmulateableArchitecture
    , intent        : IntentSpec
) -> String {
    return 
    emitScriptForApplicationAndKnobsInsertion(
          application   : application
        , warmupInputNum: warmupInputNum
        , intent        : intent
    )
    +
    emitScriptForSystemAndKnobsInsertion(
          architecture: architecture
        , intent: intent
    )
}
