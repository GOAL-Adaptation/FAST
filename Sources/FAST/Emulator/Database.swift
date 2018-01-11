/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *  pemu: Database driven emulator
 *
 *        Database Layer
 *
 *  author: Ferenc A Bartha, Adam Duracz, Dung Nguyen
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//-------------------------------

import Foundation
import LoggerAPI
import SQLite
import SQLite3

//-------------------------------

// Key prefix for initialization
fileprivate let key = ["proteus","emulator","database"]

//-------------------------------

/** Database Knobs */
class DatabaseKnobs: TextApiModule {

    let name = "databaseKnobs"
    var subModules = [String : TextApiModule]()

    // Database Knobs
    var readingMode = Knob(name: "readingMode", from: key, or: ReadingMode.Statistics)

    init() {
        self.addSubModule(newModule: readingMode)
    }

}

enum ReadingMode: String {
  case Statistics
  case Tape
}

extension ReadingMode: InitializableFromString {

  init?(from text: String) {

    switch text {

      case "Statistics": 
        self = ReadingMode.Statistics

      case "Tape": 
        self = ReadingMode.Tape

      default:
        return nil

    }
  }
}

extension ReadingMode: CustomStringConvertible {

  var description: String {

    switch self {

      case ReadingMode.Statistics: 
        return "Statistics"

      case ReadingMode.Tape: 
        return "Tape"
       
    }
  }
}

//-------------------------------

/** Database */
public class Database: TextApiModule {

  public let name = "database"
  public var subModules = [String : TextApiModule]()

  var databaseKnobs = DatabaseKnobs()

  public var database: SQLite

  public init?(databaseFile: String) {
    if !FileManager.default.fileExists(atPath: databaseFile) {
        Log.error("Failed to initialize emulation database. File does not exist: '\(databaseFile)'.")
        fatalError()
    }
    do {
        self.database = try SQLite(databaseFile)
        Log.info("Initialized emulation database from file '\(databaseFile)'.")
    } catch let exception {
        Log.error("Exception while initializing emulation database from file '\(databaseFile)': \(exception).")
        fatalError()
    }
    createStatisticalViews()

    self.addSubModule(newModule: databaseKnobs)

  }

  public convenience init?() {
    if let databaseFile = initialize(type: String.self, name: "db", from: key) {
        self.init(databaseFile: databaseFile)
    } else {
        Log.error("Failed to initialize emulation database from key '\(key)'.")
        fatalError()
    }
  }

  public func execute(script: String) throws {
      for statementInScript in script.components(separatedBy: ";") {
          if statementInScript.characters.count > 0 {
              try database.execute(statement: statementInScript)
          }
      }
  }

  /** Get the configuration Id of the current application knobs and their corresponding values from the database. 
  */
  public func getCurrentConfigurationId(application: Application) -> Int {

    var result: Int? = nil

    // Create a temporary view of all the application configurations with all the knob names and their corresponding values:
    var sqliteQuery =
      "CREATE TEMPORARY VIEW IF NOT EXISTS AllAppCfgIdView AS " +
      "SELECT [ApplicationConfiguration].[id] AS [appCfgId], " +
      "       [Knob].[name] AS [knobName], " +
      "       [ApplicationConfiguration_Application_Knob].[knobValue] AS [knobValue] " +
      "FROM   [Knob] " +
      "       INNER JOIN [Application_Knob] ON [Knob].[id] = [Application_Knob].[knobId] " +
      "       INNER JOIN [Application] ON [Application].[id] = [Application_Knob].[applicationId] " +
      "       INNER JOIN [ApplicationConfiguration_Application_Knob] ON [Application_Knob].[id] = [ApplicationConfiguration_Application_Knob].[applicationKnobId] " +
      "       INNER JOIN [ApplicationConfiguration] ON [ApplicationConfiguration].[id] = [ApplicationConfiguration_Application_Knob].[applicationConfigurationId] " +
      "WHERE  [Application].[name] =  '\(application.name)'; "

    // Execute the query:
    do {
      try database.execute(statement: sqliteQuery)
    } catch let exception {
      Log.error("Exception creating temporary view of all application configurations: \(exception).")
      fatalError("Cannot execute query creating temporary view of  all application configurations: \(sqliteQuery)")
    }
    
    // Dynamically create a query containing all the knob names and corresponding values that match with the current application configuration:
    sqliteQuery = 
      "SELECT DISTINCT appCfgId FROM AllAppCfgIdView " +
      "WHERE appCfgId NOT IN (" +
      " SELECT appCfgId FROM AllAppCfgIdView " +
      " WHERE appCfgId NOT IN ("
    var appKnobs = application.subModules["applicationKnobs"]!.getStatus()!
    if let (firstKnobName, firstKnobValueAny) = appKnobs.first,
       let firstKnobValueDict = firstKnobValueAny as? [String : Any],
       let firstKnobValue = firstKnobValueDict["value"] {
      sqliteQuery += "SELECT appCfgId FROM AllAppCfgIdView WHERE knobName = '\(firstKnobName)' AND knobValue =  \(firstKnobValue) "
      appKnobs.removeValue(forKey: firstKnobName)
    }
    for (knobName, knobValueAny) in appKnobs {
      if let knobValueDict = knobValueAny as? [String : Any],
         let knobValue = knobValueDict["value"] {
        sqliteQuery += "INTERSECT SELECT appCfgId FROM AllAppCfgIdView WHERE knobName = '\(knobName)' AND knobValue = \(knobValue) "
      }
    }
    sqliteQuery += ") )"

    // Execute the query:
    do {
      try database.forEachRow(statement: sqliteQuery, handleRow: {
            (s: SQLiteStmt, i:Int) -> () in result = s.columnInt(position: 0)
          })
    } catch let exception {
      Log.error("Exception getting the current application configuration ID: \(exception).")
      fatalError("Cannot execute query getting the current application configuration ID: \(sqliteQuery)")
    }

    // Return the application configuration ID if it exists:
    if let res = result {
      Log.debug("Read current application configuration ID from the emulation database: \(res).")
      return res
    }
    else {
      Log.error("Failed to read the current application configuration ID from the emulation database.")
      fatalError("Failed to read the current application configuration ID from the emulation database: \(sqliteQuery)")
    }
  }

/** Get the configuration Id of the current system knobs and their corresponding values from the database. 
*/
func getCurrentConfigurationId(architecture: Architecture) -> Int {

   var result: Int? = nil

  // Create a temporary view of all the system configurations with all the knob names and their corresponding values:
  var sqliteQuery =
  "CREATE TEMPORARY VIEW IF NOT EXISTS AllSysCfgIdView AS " + 
  "SELECT [SystemConfiguration].[id] AS [sysCfgId], " +
  "       [Knob].[name] AS [knobName], " +
  "       [SystemConfiguration_System_Knob].[knobValue] AS [knobValue] " +
  "FROM   [Knob] " +
  "       INNER JOIN [System_Knob] ON [Knob].[id] = [System_Knob].[knobId] " +
  "       INNER JOIN [System] ON [System].[id] = [System_Knob].[systemId] " +
  "       INNER JOIN [SystemConfiguration_System_Knob] ON [System_Knob].[id] = [SystemConfiguration_System_Knob].[systemKnobId] " +
  "       INNER JOIN [SystemConfiguration] ON [SystemConfiguration].[id] = [SystemConfiguration_System_Knob].[systemConfigurationId] " +
  "WHERE  [System].[name] = '\(architecture.name)';"

  // Execute the query:
  do {
    try database.execute(statement: sqliteQuery)
  } catch let exception {
    Log.error("Exception creating temporary view of all system configurations: \(exception).")
    fatalError("Cannot execute query creating temporary view of all system configurations: \(sqliteQuery)")
  }

  // Dynamically create a query containing all the knob names and corresponding values that match with the current application configuration:
  sqliteQuery = 
  "SELECT DISTINCT sysCfgId FROM AllSysCfgIdView " +
  "WHERE sysCfgId NOT IN (" +
  "SELECT sysCfgId FROM AllSysCfgIdView " +
  " WHERE sysCfgId NOT IN (" 
    var sysKnobs = architecture.subModules["systemConfigurationKnobs"]!.getStatus()!
    if let (firstKnobName, firstKnobValueAny) = sysKnobs.first,
       let firstKnobValueDict = firstKnobValueAny as? [String : Any],
       let firstKnobValue = firstKnobValueDict["value"] {
      sqliteQuery += "SELECT sysCfgId FROM AllSysCfgIdView WHERE knobName = '\(firstKnobName)' AND knobValue =  \(firstKnobValue) "
      sysKnobs.removeValue(forKey: firstKnobName)
    }
    for (knobName, knobValueAny) in sysKnobs {
      if let knobValueDict = knobValueAny as? [String : Any],
         let knobValue = knobValueDict["value"] {
        sqliteQuery += "INTERSECT SELECT sysCfgId FROM AllSysCfgIdView WHERE knobName = '\(knobName)' AND knobValue = \(knobValue) "
      }
    }
    sqliteQuery += ") )"

    // Execute the query:
    do {
      try database.forEachRow(statement: sqliteQuery, handleRow: {
            (s: SQLiteStmt, i:Int) -> () in  result = s.columnInt(position: 0)
          })
    } catch let exception {
      Log.error("Exception getting the current system configuration ID: \(exception).")
      fatalError("Cannot execute query getting the current system configuration ID: \(sqliteQuery)")
    }

    // Return the application configuration ID if it exists:
    if let res = result {
      Log.debug("Read the current system configuration ID from the emulation database: \(res).")
      return res
    }
    else {
      Log.error("Failed to read the current system configuration ID from the emulation database.")
      fatalError("Failed to read the current system configuration ID from the emulation database: \(sqliteQuery)")
    }
  }

  /** Create Statistical Views */
  func createStatisticalViews() {
    do {  

      var sqliteQuery: String

      // Increase cache size
      sqliteQuery =
          "PRAGMA cache_size = 10000;"
      try database.execute(statement: sqliteQuery)

      // Turn on referential integrity
      sqliteQuery =
          "PRAGMA foreign_keys=on;"
      try database.execute(statement: sqliteQuery)

      // Creating the post-warmup view
      sqliteQuery =
        "CREATE TEMPORARY VIEW PostWarmup_ApplicationSystemInputLog AS  " +
        "SELECT DISTINCT [ApplicationSystemInputLog].[applicationInputStream_applicationConfigurationId], " +
        "       [ApplicationSystemInputLog].[systemConfigurationId], " +
        "       [ApplicationSystemInputLog].[inputNumber], " +
        "       [ApplicationSystemInputLog].[deltaTime], " +
        "       [ApplicationSystemInputLog].[deltaEnergy] " +
        "FROM   [Application] " +
        "       INNER JOIN [Application_Knob] ON [Application].[id] = [Application_Knob].[applicationId] " +
        "       INNER JOIN [ApplicationConfiguration_Application_Knob] ON [Application_Knob].[id] = [ApplicationConfiguration_Application_Knob].[applicationKnobId] " +
        "       INNER JOIN [ApplicationConfiguration] ON [ApplicationConfiguration].[id] = [ApplicationConfiguration_Application_Knob].[applicationConfigurationId] " +
        "         AND [ApplicationConfiguration].[id] = [ApplicationInputStream_ApplicationConfiguration].[applicationConfigurationId] " +
        "       INNER JOIN [ApplicationInputStream] ON [Application].[id] = [ApplicationInputStream].[applicationId] " +
        "       INNER JOIN [ApplicationInputStream_ApplicationConfiguration] ON [ApplicationInputStream].[id] = [ApplicationInputStream_ApplicationConfiguration].[applicationInputId] " +
        "       INNER JOIN [ApplicationSystemInputLog] ON [ApplicationInputStream_ApplicationConfiguration].[id] = [ApplicationSystemInputLog].[applicationInputStream_applicationConfigurationId] " +
        "WHERE [ApplicationSystemInputLog].[inputNumber] > [warmupInputNum];"
      try database.execute(statement: sqliteQuery)

      Log.verbose("Created emulation database post-warmup view.")

      // Creating the statistical post-warmup view
      sqliteQuery =
        "CREATE TEMPORARY VIEW [PostWarmup_ApplicationSystemInputLog_Avg_Var] AS " +
        "SELECT [PostWarmup_ApplicationSystemInputLog].[applicationInputStream_applicationConfigurationId], " +
        "       [PostWarmup_ApplicationSystemInputLog].[systemConfigurationId], " +
        "       AVG ([PostWarmup_ApplicationSystemInputLog].[deltaTime]) AS [AvgOfDeltaTime], " +
        "       (SELECT (SUM (([deltaTime] - (SELECT AVG ([deltaTime]) " +
        "FROM   [PostWarmup_ApplicationSystemInputLog])) * ([deltaTime] - (SELECT AVG ([deltaTime]) " +
        "FROM   [PostWarmup_ApplicationSystemInputLog])))) / (COUNT ([deltaTime]) - 1) AS [Variance] " +
        "FROM   [PostWarmup_ApplicationSystemInputLog]) AS [VarOfDeltaTime], " +
        "       AVG ([PostWarmup_ApplicationSystemInputLog].[deltaEnergy]) AS [AvgOfDeltaEnergy], " +
        "       (SELECT (SUM (([deltaEnergy] - (SELECT AVG ([deltaEnergy]) " +
        "FROM   [PostWarmup_ApplicationSystemInputLog])) * ([deltaEnergy] - (SELECT AVG ([deltaEnergy]) " +
        "FROM   [PostWarmup_ApplicationSystemInputLog])))) / (COUNT ([deltaEnergy]) - 1) AS [Variance] " +
        "FROM   [PostWarmup_ApplicationSystemInputLog]) AS [VarOfDeltaEnergy] " +
        "FROM   [PostWarmup_ApplicationSystemInputLog] " +
        "GROUP  BY [PostWarmup_ApplicationSystemInputLog].[applicationInputStream_applicationConfigurationId], " +
        "          [PostWarmup_ApplicationSystemInputLog].[systemConfigurationId];"
      try database.execute(statement: sqliteQuery)
      
      Log.verbose("Created emulation database statistical post-warmup view.")

    } catch let exception {
        Log.error("Exception creating emulation database statistical tables in the emulation database: \(exception).")
        fatalError()
    }

  }

  /** Read the appropriate reference application configuration 
  * If there's a more dense profile grid, it makes sense to make different interpolation, 
  * e.g. basing on the closest intersection of profiled axes.
  * This is emphasized by keeping these IDs dynamically queried.
  */
  func getReferenceApplicationConfigurationID(application: String) -> Int {

    var result: Int? = nil

    let sqliteQuery =
    "SELECT appCfgId FROM " +
    "(SELECT [ApplicationConfiguration].[id] AS appCfgId, " +
    "        COUNT(*) AS numberOfKnobsWithReferenceValues " +
    "        FROM   [Application] " +
    "               INNER JOIN [Application_Knob] ON [Application].[id] = [Application_Knob].[applicationId] " +
    "               INNER JOIN [ApplicationConfiguration_Application_Knob] ON [Application_Knob].[id] = [ApplicationConfiguration_Application_Knob].[applicationKnobId] " +
    "               INNER JOIN [ApplicationConfiguration] ON [ApplicationConfiguration].[id] = [ApplicationConfiguration_Application_Knob].[applicationConfigurationId] " +
    "        WHERE  [Application].[name] = :1 " +
    "               AND [ApplicationConfiguration_Application_Knob].[knobValue] = [Application_Knob].[knobReferenceValue] " +
    "        GROUP BY [ApplicationConfiguration].[id] " +
    "HAVING numberOfKnobsWithReferenceValues = " +
    "(SELECT COUNT(*) AS numberOfKnobs " +
    "        FROM " +
    "        (SELECT [Knob].[name] AS [knobName] " +
    "        FROM   [Application] " +
    "               INNER JOIN [Application_Knob] ON [Application].[id] = [Application_Knob].[applicationId] " +
    "               INNER JOIN [Knob] ON [Knob].[id] = [Application_Knob].[knobId] " +
    "        WHERE  [Application].[name] = :1)));"
    do {
      try database.forEachRow(statement: sqliteQuery, doBindings: {
        (s1: SQLiteStmt) -> () in 
          try s1.bind(position: 1, application)
      }) { 
        (s2: SQLiteStmt, i:Int) -> () in result = s2.columnInt(position: 0)
      }
    } catch let exception {
      Log.error("Exception while reading the reference application configuration from the emulation database: \(exception).")
      fatalError()
    }

    if let res = result {
        Log.debug("Read reference application configuration from the emulation database: \(res).")
        return res
    }
    else {
        Log.error("Failed to read the reference application configuration from the emulation database.")
        fatalError()
    }
          
  }

  /** Read the appropriate reference system configuration 
  * If there's a more dense profile grid, it makes sense to make different interpolation, 
  * e.g. basing on the closest intersection of profiled axes.
  * This is emphasized by keeping these IDs dynamically queried.
  */
  func getReferenceSystemConfigurationID(architecture: String) -> Int {

    var result: Int? = nil

    let sqliteQuery =
    "SELECT sysCfgId " +
    "FROM " +
      "(SELECT [SystemConfiguration].[id] AS sysCfgId, " +
              "COUNT(*) AS numberOfKnobsWithReferenceValues " +
        "FROM   [System] " +
          "INNER JOIN [System_Knob] ON [System].[id] = [System_Knob].[systemId] " +
          "INNER JOIN [SystemConfiguration_System_Knob] ON [System_Knob].[id] = [SystemConfiguration_System_Knob].[systemKnobId] " +
          "INNER JOIN [SystemConfiguration] ON [SystemConfiguration].[id] = [SystemConfiguration_System_Knob].[systemConfigurationId] " +
        "WHERE  [System].[name] = :1 " +
                "AND [SystemConfiguration_System_Knob].[knobValue] = [System_Knob].[knobReferenceValue] " +
        "GROUP BY [SystemConfiguration].[id] " +
    "HAVING numberOfKnobsWithReferenceValues = " +
      "(SELECT COUNT(*) AS numberOfSystemKnobs " +
      "FROM (SELECT [Knob].[name] AS [knobName] " +
        "FROM   [System] " +
            "INNER JOIN [System_Knob] ON [System].[id] = [System_Knob].[systemId] " +
            "INNER JOIN [Knob] ON [Knob].[id] = [System_Knob].[knobId] " +
        "WHERE  [System].[name] = :1)));"
    do {
      try database.forEachRow(statement: sqliteQuery, doBindings: {
        (s1: SQLiteStmt) -> () in try s1.bind(position: 1, architecture)
      })  { (s2: SQLiteStmt, i:Int) -> () in result = s2.columnInt(position: 0) }
      } catch let exception {
        Log.error("Failed to read the reference system configuration from the emulation database: \(exception).")
        fatalError()
    }

    if let res = result {
        Log.debug("Read reference system configuration from the emulation database: \(res).")
        return res
    }
    else {
        Log.error("Failed to read the reference system configuration from the emulation database.")
        fatalError("Failed to read the reference system configuration from the emulation database: \(sqliteQuery)")
    }

  }

  /** Read the number of warmupInputs */
  func getWarmupInputs(application: String) -> Int {

    var result: Int? = nil
    
    let sqliteQuery =
      "SELECT Application.warmupInputNum " +
      "FROM Application " +
      "WHERE Application.name = :1;"
    do {
      try database.forEachRow(statement: sqliteQuery, doBindings: {
        (s1: SQLiteStmt) -> () in try s1.bind(position: 1, application)
      })  { (s2: SQLiteStmt, i:Int) -> () in result = s2.columnInt(position: 0) }
    } catch let exception {
      Log.error("Failed to read the number of warmupInputs from the emulation database: \(exception).")
      fatalError()
    }
    if let res = result {
        Log.debug("Read number of warmup inputs from the emulation database: \(res).")
        return res
    }
    else {
        Log.error("Failed to read the number of warmup inputs from the emulation database.")
        fatalError()
    }
  }

  /** Get number of inputs profiled 
  *  Obtain the number of taped inputs
  *  NOTE Asserts that from 1 to number all inputID-s are present and unique
  */
  func getNumberOfInputsProfiled( application: String, 
                                  architecture: String, 
                                  appCfg applicationConfigurationID: Int, 
                                  appInp applicationInputID: Int, 
                                  sysCfg systemConfigurationID: Int) -> Int {

    var result = 0
    
    let sqliteQuery =    
    "SELECT MAX ([ApplicationSystemInputLog].[inputNumber]) AS [MaxInputNumber], " +
    "       [Application].[name] AS [appName], " +
    "       [System].[name] AS [sysName], " +
    "       [ApplicationConfiguration].[id] AS [appCfgId], " +
    "       [ApplicationInputStream].[id] AS [appInpStrmId], " +
    "       [SystemConfiguration].[id] AS [sysConfigId] " +
    "FROM   [Application] " +
    "       INNER JOIN [ApplicationInputStream] ON [Application].[id] = [ApplicationInputStream].[applicationId] " +
    "       INNER JOIN [Application_Knob] ON [Application].[id] = [Application_Knob].[applicationId] " +
    "       INNER JOIN [ApplicationConfiguration_Application_Knob] ON [Application_Knob].[id] = [ApplicationConfiguration_Application_Knob].[applicationKnobId] " +
    "       INNER JOIN [ApplicationInputStream_ApplicationConfiguration] ON [ApplicationInputStream].[id] = [ApplicationInputStream_ApplicationConfiguration].[applicationInputId] " +
    "       INNER JOIN [ApplicationSystemInputLog] ON [ApplicationInputStream_ApplicationConfiguration].[id] = [ApplicationSystemInputLog].[applicationInputStream_applicationConfigurationId] " +
    "       INNER JOIN [SystemConfiguration] ON [SystemConfiguration].[id] = [ApplicationSystemInputLog].[systemConfigurationId] " +
    "       INNER JOIN [SystemConfiguration_System_Knob] ON [SystemConfiguration].[id] = [SystemConfiguration_System_Knob].[systemConfigurationId] " +
    "       INNER JOIN [System_Knob] ON [System_Knob].[id] = [SystemConfiguration_System_Knob].[systemKnobId] " +
    "       INNER JOIN [System] ON [System].[id] = [System_Knob].[systemId] " +
    "       INNER JOIN [ApplicationConfiguration] ON [ApplicationConfiguration].[id] = [ApplicationConfiguration_Application_Knob].[applicationConfigurationId] " +
    "       AND [ApplicationConfiguration].[id] = [ApplicationInputStream_ApplicationConfiguration].[applicationConfigurationID] " +
    "WHERE  [Application].[name] = :1 " +
    "       AND [System].[name] = :2 " +
    "       AND [ApplicationConfiguration].[id] = :3 " +
    "       AND [ApplicationInputStream].[id] = :4 " +
    "       AND [SystemConfiguration].[id] = :5 " +
    "GROUP  BY [Application].[name], " +
    "          [System].[name],  " +
    "          [ApplicationConfiguration].[id], " +
    "          [ApplicationInputStream].[id], " +
    "          [SystemConfiguration].[id];"
    do {

      try database.forEachRow(statement: sqliteQuery, doBindings: {
        (statement: SQLiteStmt) -> () in

            try statement.bind(position: 1, application)
            try statement.bind(position: 2, architecture)
            try statement.bind(position: 3, applicationConfigurationID)
            try statement.bind(position: 4, applicationInputID)
            try statement.bind(position: 5, systemConfigurationID)

      })  { (statement: SQLiteStmt, i:Int) -> () in
        result = statement.columnInt(position: 0)            
      }

    } catch let exception {
      Log.error("Failed to read the inputs profiled from the emulation database: \(exception).")
      fatalError()
    }

    return result
  }

  /** Obtain the Tape noise*/
  func getTapeNoise(application: String) -> Double {
    var result: Double? = nil
    
    let sqliteQuery =
       "SELECT JobLogParameter.tapeNoise   " +
       "FROM Application  " +
       "  INNER JOIN JobLogParameter ON JobLogParameter.applicationId = Application.id " +
       " WHERE Application.name = :1;"
    do {
      try database.forEachRow(statement: sqliteQuery, doBindings: {
        (statement: SQLiteStmt) -> () in
        try statement.bind(position: 1, application)
      })  { (statement: SQLiteStmt, i:Int) -> () in
        result = statement.columnDouble(position: 0)            
      }
    } catch let exception {
      Log.error("Failed to read the Tape noise from the emulation database: \(exception).")
      fatalError()
    }

    if let res = result {
        Log.debug("Read the tape noise from the emulation database: \(res).")
        return res
    }
    else {
        Log.error("Failed to read the tape noise from the emulation database.")
        fatalError()
    }
  }


  /** Get the application id for a given application name from the database
  */
  public func getApplicationId(application: String) -> Int {
    var result: Int? = nil
    
    let sqliteQuery =
      "SELECT [Application].[id] AS [appId] " +
      "FROM   [Application] " +
      "WHERE  [Application].[name] = :1; " 
    do {
      try database.forEachRow(statement: sqliteQuery, doBindings: {
        (s1: SQLiteStmt) -> () in try s1.bind(position: 1, application)
      })  { (s2: SQLiteStmt, i:Int) -> () in result = s2.columnInt(position: 0) }
    } catch let exception {
      let errorMessage = "Failed to read the application id for '\(application)' from the emulation database: \(exception)."
      Log.error(errorMessage)
      fatalError(errorMessage)
    }
    if let res = result {
        Log.debug("Read the application id for '\(application)' from the emulation database: \(res).")
        return res
    }
    else {
        Log.error("Failed to read the the application id for '\(application)' from the emulation database.")
        fatalError()
    }
  }

  /** Insert a knob of an application identified by its ID into a database.
  */
  public func insertKnob(applicationId: Int, knobName: String, knobType: String, referenceValue: String) {
    // TODO
  }

  /** Select which input to read in Tape mode */
  func getInputNumberToRead(inputID: Int, maximalInputID: Int, warmupInputs: Int) -> Int {
        
        // A recorded input is directly read
        if inputID <= maximalInputID {
          return inputID

        // A "non-taped" input is randomly emulated from the "non-warmup" segment
        // TODO check if range is non-empty warmupInputs + 1 < maximalInputID
        } else {
          let extraInputs = inputID - maximalInputID
          let offsetRange = maximalInputID - (warmupInputs + 1)

          // offset \in 1 .. offsetRange
          let offset = (extraInputs % offsetRange == 0) ? offsetRange : (extraInputs % offsetRange)

          // Backward / Forward
          enum ReadingDirection {
            case Backward
            case Forward
            // NOTE extraInputs >= 1 is guaranteed
          }

          let readDirection: ReadingDirection
          
          readDirection = ( ((extraInputs - 1) / offsetRange) % 2 == 0 ) ? ReadingDirection.Backward : ReadingDirection.Forward

          // Read the tape back and forth

          // Backward reading from [maximalInputID]   - 1   to [warmupInputs + 1]
          // Forward  reading from [warmupInputs + 1] + 1   to [maximalInputID]
          return (readDirection == ReadingDirection.Backward) ? (maximalInputID - offset) : ((warmupInputs + 1) + offset)
        }

  }

  /** Obtain outliers for the application */
  func obtainOutliers(application: String) -> (Double, Double) {

    var result = (0.0, 0.0)
    
    let sqliteQuery =
   "SELECT JobLogParameter.timeOutlier, JobLogParameter.energyOutlier  " +
    "FROM Application " +
    "INNER JOIN JobLogParameter ON JobLogParameter.applicationId = Application.id " +
    " WHERE Application.name = :1;"
    do {
      try database.forEachRow(statement: sqliteQuery, doBindings: {
        (statement: SQLiteStmt) -> () in
        try statement.bind(position: 1, application)
      })  { (statement: SQLiteStmt, i:Int) -> () in
        result = (statement.columnDouble(position: 0), statement.columnDouble(position: 1))            
      }
    } catch let exception {
      Log.error("Failed to read the outliers for the application from the emulation database: \(exception).")
      fatalError()
    }

    return result
  }

  /** An ApplicationInputStream Id is uniquely determined by an application name
  * and an input stream name.
  */
  public func getApplicatioInputStreamId(application: String, // name of application
                                  inputStream: String  // name of input stream
                                  ) -> Int {
    var result: Int? = nil

    let sqliteQuery = 
    "SELECT [ApplicationInputStream].[id], " +
    "       [Application].[name] AS [applicationName], " +
    "       [ApplicationInputStream].[name] AS [inputStreamName] " +
    "FROM   [Application] " +
    "       INNER JOIN [ApplicationInputStream] ON [Application].[id] = [ApplicationInputStream].[applicationId] " +
    "WHERE  [Application].[name] = :1 " +
    "       AND [ApplicationInputStream].[name] = :2;"

    do {
        try database.forEachRow(statement: sqliteQuery, doBindings: {
          (s1: SQLiteStmt) -> () in 
            try s1.bind(position: 1, application)
            try s1.bind(position: 2, inputStream)
        }) { 
          (s2: SQLiteStmt, i:Int) -> () in result = s2.columnInt(position: 0)
        }
      } catch let exception {
        let errorMessage = "Exception while reading the application input stream id from the emulation database: \(exception)."
        Log.error(errorMessage)
        fatalError(errorMessage)
      }

      if let res = result {
          Log.debug("Read application input stream id from the emulation database: \(res).")
          return res
      }
      else {
        let errorMessage = "Failed to read the application input stream id from the emulation database."
        Log.error(errorMessage)
        fatalError(errorMessage)
      }
  }

  /**
  */
  public func getApplicationInputStreamApplicationConfigurationId
    ( application: String // application name
    , inputStream: String // input stream name
    , applicationConfigurationId: Int 
    ) -> Int {
      
      var result: Int? = nil
      let sqliteQuery =
      "SELECT [ApplicationInputStream_ApplicationConfiguration].[id] AS [appInputStreamAppCfgId] " +
      "FROM   [Application] " +
      "       INNER JOIN [ApplicationInputStream] ON [Application].[id] = [ApplicationInputStream].[applicationId] " +
      "       INNER JOIN [ApplicationInputStream_ApplicationConfiguration] ON [ApplicationInputStream].[id] = [ApplicationInputStream_ApplicationConfiguration].[applicationInputId] " +
      "       INNER JOIN [ApplicationConfiguration] ON [ApplicationConfiguration].[id] = [ApplicationInputStream_ApplicationConfiguration].[applicationConfigurationID] " +
      "WHERE  [Application].[name] = :1 " +
      "       AND [ApplicationInputStream].[name] = :2 " +
      "       AND [ApplicationConfiguration].[id] = :3;"

    do {
        try database.forEachRow(statement: sqliteQuery, doBindings: {
          (s1: SQLiteStmt) -> () in 
            try s1.bind(position: 1, application)
            try s1.bind(position: 2, inputStream)
            try s1.bind(position: 3, applicationConfigurationId)
        }) { 
          (s2: SQLiteStmt, i:Int) -> () in result = s2.columnInt(position: 0)
        }
      } catch let exception {
        let errorMessage = "Exception while reading the applicationInputStream_applicationConfigurationId from the emulation database: \(exception)."
        Log.error(errorMessage)
        fatalError(errorMessage)
      }

      if let res = result {
          Log.debug("Read applicationInputStream_applicationConfigurationId from the emulation database: \(res).")
          return res
      }
      else {
        let errorMessage = "Failed to read applicationInputStream_applicationConfigurationId from the emulation database."
        Log.error(errorMessage)
        fatalError(errorMessage)
      }
  }

  //-------------------------------

  /** Read Delta from the SQL Database */
  func readDelta(application: String, 
                architecture: String, 
                appCfg applicationConfigurationID: Int, 
                appInp applicationInputID: Int, 
                sysCfg systemConfigurationID: Int, 
                processing progressCounter: Int) 
                    ->
                (Int, Int) {

    let rescaleFactorMean     = 1.0
    var rescaleFactorVariance = 1.0

    let warmupInputs = getWarmupInputs(application: application)

    // Differentiate between reading modes
    switch databaseKnobs.readingMode.get() {

      case ReadingMode.Tape:
        // Read the tape

        let maximalInputID = getNumberOfInputsProfiled(application: application, architecture: architecture, appCfg: applicationConfigurationID, appInp: applicationInputID, sysCfg: systemConfigurationID)

        //----

        var readTime = 0;
        var readEnergy = 0;

        let tapeNoise = getTapeNoise(application: application)

        let entryID = getInputNumberToRead(inputID: progressCounter, maximalInputID: maximalInputID, warmupInputs: warmupInputs)

        let sqliteQuery =
        "SELECT DISTINCT [ApplicationSystemInputLog].[deltaTime], " +
        "       [ApplicationSystemInputLog].[deltaEnergy] " +
        "FROM   [Application] " +
        "       INNER JOIN [Application_Knob] ON [Application].[id] = [Application_Knob].[applicationId] " +
        "       INNER JOIN [ApplicationConfiguration_Application_Knob] ON [Application_Knob].[id] = [ApplicationConfiguration_Application_Knob].[applicationKnobId] " +
        "       INNER JOIN [ApplicationConfiguration] ON [ApplicationConfiguration].[id] = [ApplicationConfiguration_Application_Knob].[applicationConfigurationId] " +
        "       AND [ApplicationConfiguration].[id] = [ApplicationInputStream_ApplicationConfiguration].[applicationConfigurationId] " +
        "       INNER JOIN [ApplicationInputStream] ON [Application].[id] = [ApplicationInputStream].[applicationId] " +
        "       INNER JOIN [ApplicationInputStream_ApplicationConfiguration] ON [ApplicationInputStream].[id] = [ApplicationInputStream_ApplicationConfiguration].[applicationInputId] " +
        "       INNER JOIN [ApplicationSystemInputLog] ON [ApplicationInputStream_ApplicationConfiguration].[id] = [ApplicationSystemInputLog].[applicationInputStream_applicationConfigurationId] " +
        "       INNER JOIN [SystemConfiguration] ON [SystemConfiguration].[id] = [ApplicationSystemInputLog].[systemConfigurationId] " +
        "       INNER JOIN [SystemConfiguration_System_Knob] ON [SystemConfiguration].[id] = [SystemConfiguration_System_Knob].[systemConfigurationId] " +
        "       INNER JOIN [System_Knob] ON [System_Knob].[id] = [SystemConfiguration_System_Knob].[systemKnobId] " + 
        "       INNER JOIN [System] ON [System].[id] = [System_Knob].[systemId] " +
        "WHERE  [Application].[name] = :1 " +
        "       AND [System].[name] = :2 " +
        "       AND [ApplicationConfiguration].[id] = :3 " +
        "       AND [ApplicationInputStream].[id] = :4 " +
        "       AND [SystemConfiguration].[id] = :5 " +
        "       AND [ApplicationSystemInputLog].[inputNumber] = :6;"             
        do {
          try database.forEachRow(statement: sqliteQuery, doBindings: {
            (statement: SQLiteStmt) -> () in

                try statement.bind(position: 1, application)
                try statement.bind(position: 2, architecture)
                try statement.bind(position: 3, applicationConfigurationID)
                try statement.bind(position: 4, applicationInputID)
                try statement.bind(position: 5, systemConfigurationID)
                try statement.bind(position: 6, entryID)

          })  {(statement: SQLiteStmt, i:Int) -> () in
            readTime = statement.columnInt(position: 0)
            readEnergy = statement.columnInt(position: 1)               
          }
        } catch let exception {
          Log.error("Failed to read the delta from the emulation database (in Tape reading mode): \(exception).")
          fatalError()
        }

        // Adding noise
        let deltas =  ( readTime + Int(randomizerWhiteGaussianNoise(deviation: Double(readTime) * tapeNoise))
                      , readEnergy + Int(randomizerWhiteGaussianNoise(deviation: Double(readEnergy) * tapeNoise)) )
        Log.debug("Read (time,energy) deltas from emulation database: \((readTime,readEnergy)). With (Tape) noise: \(deltas).")        

        return deltas

      case ReadingMode.Statistics:
        // Obtain the means and deviations of deltaEnergy and deltaTime

        let sqliteQuery: String

        // warmup: given a global app ID, a global sys ID and a input ID, find delta time and energy and their corresponding stdev = 0
        if progressCounter <= warmupInputs {

          sqliteQuery =
        "SELECT DISTINCT [ApplicationSystemInputLog].[deltaTime], 0 AS VarOfDeltaTime," +
        "       [ApplicationSystemInputLog].[deltaEnergy], 0 AS VarOfDeltaEnergy " +
        "FROM   [Application] " +
        "       INNER JOIN [Application_Knob] ON [Application].[id] = [Application_Knob].[applicationId] " +
        "       INNER JOIN [ApplicationConfiguration_Application_Knob] ON [Application_Knob].[id] = [ApplicationConfiguration_Application_Knob].[applicationKnobId] " +
        "       INNER JOIN [ApplicationConfiguration] ON [ApplicationConfiguration].[id] = [ApplicationConfiguration_Application_Knob].[applicationConfigurationId] " +
        "       AND [ApplicationConfiguration].[id] = [ApplicationInputStream_ApplicationConfiguration].[applicationConfigurationId] " +
        "       INNER JOIN [ApplicationInputStream] ON [Application].[id] = [ApplicationInputStream].[applicationId] " +
        "       INNER JOIN [ApplicationInputStream_ApplicationConfiguration] ON [ApplicationInputStream].[id] = [ApplicationInputStream_ApplicationConfiguration].[applicationInputId] " +
        "       INNER JOIN [ApplicationSystemInputLog] ON [ApplicationInputStream_ApplicationConfiguration].[id] = [ApplicationSystemInputLog].[applicationInputStream_applicationConfigurationId] " +
        "       INNER JOIN [SystemConfiguration] ON [SystemConfiguration].[id] = [ApplicationSystemInputLog].[systemConfigurationId] " +
        "       INNER JOIN [SystemConfiguration_System_Knob] ON [SystemConfiguration].[id] = [SystemConfiguration_System_Knob].[systemConfigurationId] " +
        "       INNER JOIN [System_Knob] ON [System_Knob].[id] = [SystemConfiguration_System_Knob].[systemKnobId] " + 
        "       INNER JOIN [System] ON [System].[id] = [System_Knob].[systemId] " +
        "WHERE  [Application].[name] = :1 " +
        "       AND [System].[name] = :2 " +
        "       AND [ApplicationConfiguration].[id] = :3 " +
        "       AND [ApplicationInputStream].[id] = :4 " +
        "       AND [SystemConfiguration].[id] = :5 " +
        "       AND [ApplicationSystemInputLog].[inputNumber] = :6;"     

        // post-warmup: given a global app ID, a global sys ID, find average delta time and energy and their corresponding variances:
        } else {

          sqliteQuery =
        "SELECT DISTINCT [PostWarmup_ApplicationSystemInputLog_Avg_Var].[AvgOfDeltaTime], [PostWarmup_ApplicationSystemInputLog_Avg_Var].[VarOfDeltaTime], " +
        "       [PostWarmup_ApplicationSystemInputLog_Avg_Var].[AvgOfDeltaEnergy], [PostWarmup_ApplicationSystemInputLog_Avg_Var].[VarOfDeltaEnergy] " +
        "FROM   [Application] " +
        "       INNER JOIN [Application_Knob] ON [Application].[id] = [Application_Knob].[applicationId] " +
        "       INNER JOIN [ApplicationConfiguration_Application_Knob] ON [Application_Knob].[id] = [ApplicationConfiguration_Application_Knob].[applicationKnobId] " +
        "       INNER JOIN [ApplicationConfiguration] ON [ApplicationConfiguration].[id] = [ApplicationConfiguration_Application_Knob].[applicationConfigurationId] " +
        "       AND [ApplicationConfiguration].[id] = [ApplicationInputStream_ApplicationConfiguration].[applicationConfigurationId] " +
        "       INNER JOIN [ApplicationInputStream] ON [Application].[id] = [ApplicationInputStream].[applicationId] " +
        "       INNER JOIN [ApplicationInputStream_ApplicationConfiguration] ON [ApplicationInputStream].[id] = [ApplicationInputStream_ApplicationConfiguration].[applicationInputId] " +
        "       INNER JOIN [PostWarmup_ApplicationSystemInputLog_Avg_Var] ON [ApplicationInputStream_ApplicationConfiguration].[id] = [PostWarmup_ApplicationSystemInputLog_Avg_Var].[applicationInputStream_applicationConfigurationId] " +
        "       INNER JOIN [SystemConfiguration] ON [SystemConfiguration].[id] = [PostWarmup_ApplicationSystemInputLog_Avg_Var].[systemConfigurationId] " +
        "       INNER JOIN [SystemConfiguration_System_Knob] ON [SystemConfiguration].[id] = [SystemConfiguration_System_Knob].[systemConfigurationId] " +
        "       INNER JOIN [System_Knob] ON [System_Knob].[id] = [SystemConfiguration_System_Knob].[systemKnobId] " +
        "       INNER JOIN [System] ON [System].[id] = [System_Knob].[systemId] " +
        "WHERE  [Application].[name] = :1 " +
        "       AND [System].[name] = :2 " +
        "       AND [ApplicationConfiguration].[id] = :3" +
        "       AND [ApplicationInputStream].[id] = :4 " +
        "       AND [SystemConfiguration].[id] = :5;"
        }

        var meanDeltaTime = 0
        var deviationDeltaTime = 0
        var meanDeltaEnergy = 0
        var deviationDeltaEnergy = 0

        do {

          try database.forEachRow(statement: sqliteQuery, doBindings: {

            (statement: SQLiteStmt) -> () in

                try statement.bind(position: 1, application)
                try statement.bind(position: 2, architecture)
                try statement.bind(position: 3, applicationConfigurationID)
                try statement.bind(position: 4, applicationInputID)
                try statement.bind(position: 5, systemConfigurationID)

              // warmup data requires the inputID
              if progressCounter <= warmupInputs {
                try statement.bind(position: 6, progressCounter)
              }

          })  {(statement: SQLiteStmt, i:Int) -> () in

            meanDeltaTime = statement.columnInt(position: 0)
            deviationDeltaTime = Int(sqrt(Double(statement.columnInt(position: 1))))
            meanDeltaEnergy = statement.columnInt(position: 2)
            deviationDeltaEnergy = Int(sqrt(Double(statement.columnInt(position: 3))))
              
          }

        } catch let exception {
          Log.error("Failed to read the delta from the emulation database (in Statistics reading mode): \(exception).")
          fatalError()
        }

        let (timeOutlier, energyOutlier) = obtainOutliers(application: application)

        // Eliminate outliers
        switch application {

          // FIXME Move this into Application instance for x264
          case "x264":
            randomizerEliminateOutliers(measurement: meanDeltaTime,   error: deviationDeltaTime,   factor: &rescaleFactorVariance, safetyMargin: timeOutlier)
            randomizerEliminateOutliers(measurement: meanDeltaEnergy, error: deviationDeltaEnergy, factor: &rescaleFactorVariance, safetyMargin: energyOutlier)

          default:
            // Do not eliminate outliers for this application
            break

        }

        // Adding noise
        let deltas = ( Int(Double(meanDeltaTime)   * rescaleFactorMean + randomizerWhiteGaussianNoise(deviation: Double(deviationDeltaTime)   * rescaleFactorVariance)) 
                     , Int(Double(meanDeltaEnergy) * rescaleFactorMean + randomizerWhiteGaussianNoise(deviation: Double(deviationDeltaEnergy) * rescaleFactorVariance)) )        
        Log.debug("Read mean (time,energy) deltas from emulation database: \((meanDeltaTime,meanDeltaEnergy)). With (Statistics) noise: \(deltas).")        

        return deltas

    }
  }

    /** Insert an application name into the database
    * only if the application name does not exist in the database
    */
    public func insertApplication(application: String, warmupNumber: Int) {
      let sqliteQuery = "INSERT INTO Application(name, warmupInputNum) VALUES(:1, :2); "
      do {
        try database.execute(statement: "BEGIN; ")
        try database.execute(statement: sqliteQuery, doBindings: {
        (s: SQLiteStmt) -> () in
        try s.bind(position: 1, application)
        try s.bind(position: 2, warmupNumber)
        print("DXN_DEBUG >>>> insertApplication \(sqliteQuery)")
        })
        try database.execute(statement: "COMMIT;")
        } catch let exception {
        let errorMessage = "Failed to insert '\(application)' into the emulation database: \(exception)."
        Log.error(errorMessage)
        fatalError(errorMessage)
      }
    }

    /** Insert an input stream name for an application identified by its ID
    * into a database
    */
    public func insertInputStream(inputStream: String, applicationId: Int) {
      let sqliteQuery =
      "INSERT OR IGNORE INTO [ApplicationInputStream]([name], [applicationId]) VALUES(:1, :2);"
      do {
      try database.execute(statement: sqliteQuery, doBindings: {
      (s: SQLiteStmt) -> () in
      try s.bind(position: 1, inputStream)
      try s.bind(position: 2, applicationId)
      })
      } catch let exception {
      let errorMessage = "Failed to insert input stream '\(inputStream)' for application ID \(applicationId) into the emulation database: \(exception)."
      Log.error(errorMessage)
      fatalError(errorMessage)
    }
  }
//-------------------------------



}
