/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *  pemu: Database driven emulator
 *
 *        Database Layer
 *
 *  author: Ferenc A Bartha, Adam Duracz
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

  /** Get Configuration Id from DB */
  public func getConfigurationId(application: Application) -> Int {

    var result: Int = 0

    let sqliteQuery =
        " SELECT AppsInputsConfigs.appCfgID " + 
        "   FROM AppsInputs " + 
        "        INNER JOIN AppsInputsConfigs ON AppsInputs.app_appInpID = AppsInputsConfigs.app_appInpID " +
        "        INNER JOIN Applications ON Applications.appID = AppsInputs.appID " + 
        " " + 
        "  WHERE Applications.appName = :1 " + 
        "    AND AppsInputsConfigs.cdr = :2 " + 
        "    AND AppsInputsConfigs.fdr = :3 " + 
        "    AND AppsInputsConfigs.numRanges = :4 " + 
        "    AND AppsInputsConfigs.numBeams = :5"

    do {
      try database.forEachRow(statement: sqliteQuery, doBindings: {

        (statement: SQLiteStmt) -> () in

        try statement.bind(position: 1, application.name)
        try statement.bind(position: 2, 1)
        try statement.bind(position: 3, 1)
        try statement.bind(position: 4, 8192)
        try statement.bind(position: 5, 64)

      })  { (statement: SQLiteStmt, i:Int) -> () in

        result = statement.columnInt(position: 0)

      }
      Log.debug("Successfully read configuration ID \(result) from emulation database.")
    } catch {
      Log.error("Error running query.")
    }

    return result
  }

  /** Create Statistical Views */
  func createStatisticalViews() {
    do {  

      var sqliteQuery: String
      // Loading extensions
      database.enableLoadExtension()

      // TODO compile extensions in project
      if let extensionLocation = initialize(type: String.self, from: key.appended(with: "extensionLocation")) {
        sqliteQuery =
            "SELECT load_extension('" + extensionLocation + "');"
        do {
          try database.execute(statement: sqliteQuery)
          Log.verbose("Loaded emulation database extensions from '\(extensionLocation)'.")
        }
        catch {
          Log.verbose("Failed to load emulation database extensions from '\(extensionLocation)'.")
        }
      }

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
        "CREATE TEMPORARY VIEW PostWarmup_App_Sys_JobLogs AS " +
        "  SELECT [App_Sys_JobLogs].[app_appInp_appCfgID], " +
        "         [App_Sys_JobLogs].[sys_sysCfgID], " +
        "         [App_Sys_JobLogs].[jobID], " +
        "         [App_Sys_JobLogs].[delta_time], " +
        "         [App_Sys_JobLogs].[delta_energy], " +
        "         [App_Sys_JobLogs].[instructionCount] " +
        "  FROM   ([Applications] " +
        "         INNER JOIN ([AppsInputs] " +
        "         INNER JOIN [AppsInputsConfigs] ON [AppsInputs].[app_appInpID] = [AppsInputsConfigs].[app_appInpID]) ON [Applications].[appID] = [AppsInputs].[appID]) " +
        "         INNER JOIN [App_Sys_JobLogs] ON [AppsInputsConfigs].[app_appInp_appCfgID] = [App_Sys_JobLogs].[app_appInp_appCfgID] " +
        "  WHERE  ((([App_Sys_JobLogs].[jobID]) > [warmupJobNum]))"
      try database.execute(statement: sqliteQuery)

      Log.verbose("Created emulation database post-warmup view.")

      // Creating the statistical post-warmup view
      sqliteQuery =
        "CREATE TEMPORARY VIEW App_Sys_Logs_Avg_Stdev AS " +
        "  SELECT        [PostWarmup_App_Sys_JobLogs].[app_appInp_appCfgID], " +
        "                [PostWarmup_App_Sys_JobLogs].[sys_sysCfgID], " +
        "         AVG   ([PostWarmup_App_Sys_JobLogs].[delta_time])       AS [AvgOfdelta_time], " +
        "         STDEV ([PostWarmup_App_Sys_JobLogs].[delta_time])       AS [StDevOfdelta_time], " +
        "         AVG   ([PostWarmup_App_Sys_JobLogs].[delta_energy])     AS [AvgOfdelta_energy], " +
        "         STDEV ([PostWarmup_App_Sys_JobLogs].[delta_energy])     AS [StDevOfdelta_energy], " +
        "         AVG   ([PostWarmup_App_Sys_JobLogs].[instructionCount]) AS [AvgOfinstructionCount], " +
        "         STDEV ([PostWarmup_App_Sys_JobLogs].[instructionCount]) AS [StDevOfinstructionCount] " +
        "  FROM     [PostWarmup_App_Sys_JobLogs] " +
        "    GROUP BY " +
        "      [PostWarmup_App_Sys_JobLogs].[app_appInp_appCfgID], [PostWarmup_App_Sys_JobLogs].[sys_sysCfgID]"
      try database.execute(statement: sqliteQuery)
      
      Log.verbose("Created emulation database statistical post-warmup view.")

    } catch let exception {
        Log.error("Failure creating emulation database statistical tables in the emulation database: \(exception).")
        fatalError()
    }

  }

  /** Read the appropriate reference application configuration */
  func getReferenceApplicationConfigurationID(application: String) -> Int {

    // If there's a more dense profile grid, it makes sense to make different interpolation, e.g. basing on the closest intersection of profiled axes.
    // This is emphasized by keeping these IDs dynamically queried.
    var result: Int? = nil

    let sqliteQuery =
      "SELECT appCfgID " + 
      "  FROM AppsInputsConfigs " + 
      "       INNER JOIN AppsInputs ON AppsInputs.app_appInpID = AppsInputsConfigs.app_appInpID " + 
      "       INNER JOIN Applications ON Applications.appID = AppsInputs.appID " + 
      " " + 
      " WHERE AppsInputsConfigs.isReference = 1 " + 
      "   AND Applications.appName = :1"

    do {

      try database.forEachRow(statement: sqliteQuery, doBindings: {

        (statement: SQLiteStmt) -> () in

        try statement.bind(position: 1, application)

      })  {(statement: SQLiteStmt, i:Int) -> () in

        result = statement.columnInt(position: 0)

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

  /** Read the appropriate reference system configuration */
  func getReferenceSystemConfigurationID(architecture: String) -> Int {

    // If there's a more dense profile grid, it makes sense to make different interpolation, e.g. basing on the closest intersection of profiled axes.
    // This is emphasized by keeping these IDs dynamically queried.
    var result = 0;

    let sqliteQuery =
      "SELECT SystemsConfigs.sysCfgID " + 
      "  FROM SystemsConfigs " + 
      "       INNER JOIN Systems ON Systems.sysID = SystemsConfigs.sysID " + 
      " " + 
      " WHERE SystemsConfigs.isReference = 1 " + 
      "   AND Systems.sysName = :1"

    do {

      try database.forEachRow(statement: sqliteQuery, doBindings: {

        (statement: SQLiteStmt) -> () in

        try statement.bind(position: 1, architecture)

      })  {(statement: SQLiteStmt, i:Int) -> () in

        result = statement.columnInt(position: 0)

      }

    } catch let exception {
      Log.error("Failed to read the reference system configuration from the emulation database: \(exception).")
      fatalError()
    }

    return result
  }

  /** Read the number of warmupInputs */
  func getWarmupInputs(application: String) -> Int {

    var result = 0
    
    let sqliteQuery =
      "SELECT Applications.warmupJobNum " + 
      "  FROM Applications " + 
      " " + 
      " WHERE Applications.appName = :1"

    do {
      try database.forEachRow(statement: sqliteQuery, doBindings: {

        (statement: SQLiteStmt) -> () in

        try statement.bind(position: 1, application)

      })  { (statement: SQLiteStmt, i:Int) -> () in

        result = statement.columnInt(position: 0)   

      }
    } catch let exception {
      Log.error("Failed to read the number of warmupInputs from the emulation database: \(exception).")
      fatalError()
    }

    return result

  }

  /** Get number of inputs profiled */
  func getNumberOfInputsProfiled( application: String, 
                                  architecture: String, 
                                  appCfg applicationConfigurationID: Int, 
                                  appInp applicationInputID: Int, 
                                  sysCfg systemConfigurationID: Int) -> Int {
   // Obtain the number of taped inputs
   // NOTE Asserts that from 1 to number all inputID-s are present and unique


    var result = 0
    
    let sqliteQuery =
      "SELECT max(App_Sys_JobLogs.jobID) " + 
      "  FROM AppsInputs " + 
      "       INNER JOIN SystemsConfigs ON SystemsConfigs.sys_sysCfgID = App_Sys_JobLogs.sys_sysCfgID" + 
      "       INNER JOIN Systems ON SystemsConfigs.sysID = Systems.sysID " + 
      "       INNER JOIN AppsInputsConfigs ON AppsInputs.app_appInpID = AppsInputsConfigs.app_appInpID" + 
      "       INNER JOIN App_Sys_JobLogs ON AppsInputsConfigs.app_appInp_appCfgID = App_Sys_JobLogs.app_appInp_appCfgID " + 
      " " + 
      " WHERE AppsInputs.appID = :1 " + 
      "   AND AppsInputs.appInpID = :2 " + 
      "   AND AppsInputsConfigs.appCfgID = :3 " + 
      "   AND Systems.sysName = :4 " + 
      "   AND SystemsConfigs.sysCfgID = :5"

    do {

      try database.forEachRow(statement: sqliteQuery, doBindings: {

        (statement: SQLiteStmt) -> () in

        try statement.bind(position: 1, application)
        try statement.bind(position: 2, applicationInputID)
        try statement.bind(position: 3, applicationConfigurationID)
        try statement.bind(position: 4, architecture)
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

    var result = 0.0
    
    let sqliteQuery =
       "SELECT JobLogs_Parameters.tapeNoise " + 
       "  FROM Applications " + 
       "       INNER JOIN JobLogs_Parameters ON JobLogs_Parameters.appID = Applications.appID " + 
       " " + 
       " WHERE Applications.appName = :1"

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

    return result
            
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
        "SELECT JobLogs_Parameters.timeOutlier, JobLogs_Parameters.energyOutlier " + 
        "  FROM Applications " + 
        "       INNER JOIN JobLogs_Parameters ON JobLogs_Parameters.appID = Applications.appID " + 
        " " + 
        " WHERE Applications.appName = :1"

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
          "SELECT App_Sys_JobLogs.delta_time, App_Sys_JobLogs.delta_energy " + 
          "  FROM AppsInputs " + 
          "       INNER JOIN Applications      ON Applications.appID = AppsInputs.appID " + 
          "       INNER JOIN AppsInputsConfigs ON AppsInputs.app_appInpID = AppsInputsConfigs.app_appInpID " + 
          "       INNER JOIN App_Sys_JobLogs   ON AppsInputsConfigs.app_appInp_appCfgID = App_Sys_JobLogs.app_appInp_appCfgID " + 
          "       INNER JOIN SystemsConfigs    ON SystemsConfigs.sys_sysCfgID = App_Sys_JobLogs.sys_sysCfgID " + 
          "       INNER JOIN Systems           ON SystemsConfigs.sysID = Systems.sysID " + 
          " " + 
          " WHERE Applications.appName = :1 " + 
          "   AND AppsInputs.appInpID = :2 " + 
          "   AND AppsInputsConfigs.appCfgID = :3 " + 
          "   AND Systems.sysName = :4 " + 
          "   AND SystemsConfigs.sysCfgID = :5 " + 
          "   AND App_Sys_JobLogs.jobID = :6"
        
        do {

          try database.forEachRow(statement: sqliteQuery, doBindings: {

            (statement: SQLiteStmt) -> () in

              try statement.bind(position: 1, application)
              try statement.bind(position: 2, applicationInputID)
              try statement.bind(position: 3, applicationConfigurationID)
              try statement.bind(position: 4, architecture)
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
            "SELECT App_Sys_JobLogs.delta_time, 0 AS StDevOfdelta_time, App_Sys_JobLogs.delta_energy, 0 AS StDevOfdelta_energy, " + 
            "       App_Sys_JobLogs.instructionCount, 0 AS StDevOfinstructionCount " + 
            "  FROM AppsInputs " + 
            "       INNER JOIN Applications      ON Applications.appID = AppsInputs.appID " + 
            "       INNER JOIN SystemsConfigs    ON SystemsConfigs.sys_sysCfgID = App_Sys_JobLogs.sys_sysCfgID" + 
            "       INNER JOIN AppsInputsConfigs ON AppsInputs.app_appInpID = AppsInputsConfigs.app_appInpID" + 
            "       INNER JOIN App_Sys_JobLogs   ON AppsInputsConfigs.app_appInp_appCfgID = App_Sys_JobLogs.app_appInp_appCfgID" + 
            "       INNER JOIN Systems           ON SystemsConfigs.sysID = Systems.sysID " + 
            " " + 
            " WHERE Applications.appName = :1 " + 
            "   AND AppsInputs.appInpID = :2 " + 
            "   AND AppsInputsConfigs.appCfgID = :3 " + 
            "   AND Systems.sysName = :4 " + 
            "   AND SystemsConfigs.sysCfgID = :5 " + 
            "   AND App_Sys_JobLogs.jobID = :6"

        // post-warmup: given a global app ID, a global sys ID, find average delta time and energy and their corresponding stdev:
        } else {

          sqliteQuery =
            "SELECT App_Sys_Logs_Avg_Stdev.AvgOfdelta_time, App_Sys_Logs_Avg_Stdev.StDevOfdelta_time, " + 
            "       App_Sys_Logs_Avg_Stdev.AvgOfdelta_energy, App_Sys_Logs_Avg_Stdev.StDevOfdelta_energy " + 
            "  FROM AppsInputs " + 
            "       INNER JOIN Applications           ON Applications.appID = AppsInputs.appID " + 
            "       INNER JOIN AppsInputsConfigs      ON AppsInputs.app_appInpID = AppsInputsConfigs.app_appInpID " +
            "       INNER JOIN App_Sys_Logs_Avg_Stdev ON AppsInputsConfigs.app_appInp_appCfgID = App_Sys_Logs_Avg_Stdev.app_appInp_appCfgID " + 
            "       INNER JOIN SystemsConfigs         ON SystemsConfigs.sys_sysCfgID = App_Sys_Logs_Avg_Stdev.sys_sysCfgID " + 
            "       INNER JOIN Systems                ON SystemsConfigs.sysID = Systems.sysID " + 
            " " + 
            " WHERE Applications.appName = :1 " + 
            "   AND AppsInputs.appInpID = :2 " + 
            "   AND AppsInputsConfigs.appCfgID = :3 " + 
            "   AND Systems.sysName = :4 " + 
            "   AND SystemsConfigs.sysCfgID = :5 "

        }

        var meanDeltaTime = 0
        var deviationDeltaTime = 0
        var meanDeltaEnergy = 0
        var deviationDeltaEnergy = 0

        do {

          try database.forEachRow(statement: sqliteQuery, doBindings: {

            (statement: SQLiteStmt) -> () in

              try statement.bind(position: 1, application)
              try statement.bind(position: 2, applicationInputID)
              try statement.bind(position: 3, applicationConfigurationID)
              try statement.bind(position: 4, architecture)
              try statement.bind(position: 5, systemConfigurationID)

              // warmup data requires the inputID
              if progressCounter <= warmupInputs {
                try statement.bind(position: 6, progressCounter)
              }

          })  {(statement: SQLiteStmt, i:Int) -> () in

            meanDeltaTime = statement.columnInt(position: 0)
            deviationDeltaTime = statement.columnInt(position: 1)
            meanDeltaEnergy = statement.columnInt(position: 2)
            deviationDeltaEnergy = statement.columnInt(position: 3)
                
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
}

//-------------------------------
