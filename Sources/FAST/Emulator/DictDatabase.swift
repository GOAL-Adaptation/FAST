import Foundation
import LoggerAPI

//-------------------------------

// Key prefix for initialization
fileprivate let key = ["proteus","emulator","database"]

//-------------------------------

/** Database */
public class DictDatabase: TextApiModule, Database {

  public let name = "database"
  public var subModules = [String : TextApiModule]()

  var databaseKnobs = DatabaseKnobs()

  // Types and type aliases
  typealias ApplicationConfigurationId = Int // NOTE: This is different from the kid field of the KnobSettings class!
  typealias SystemConfigurationId      = Int // NOTE: This is different from the kid field of the KnobSettings class!
  typealias ApplicationId              = Int 
  typealias ApplicationInputId         = Int
  typealias ApplicationInputStreamId   = Int
  typealias ApplicationName            = String
  typealias ArchitectureName           = String
  typealias ApplicationInputStreamName = String
  typealias TimeOutlier                = Double
  typealias EnergyOutlier              = Double
  typealias Iteration                  = Int
  typealias TimeDelta                  = Double
  typealias EnergyDelta                = Double

  struct ProfileEntryId: Hashable, Codable { // NOTE: Corresponds to a single profiled app+sys configuration
    let applicationConfigurationId : ApplicationConfigurationId
    let applicationInputId         : ApplicationInputId
    let systemConfigurationId      : SystemConfigurationId
    var hashValue: Int {
       return applicationConfigurationId ^ (applicationInputId &* 16777619) ^ (systemConfigurationId &* 16777619)
    }
    static func == (lhs: ProfileEntryId, rhs: ProfileEntryId) -> Bool {
      return 
        lhs.applicationConfigurationId == rhs.applicationConfigurationId && 
        lhs.applicationInputId         == rhs.applicationInputId         && 
        lhs.systemConfigurationId      == rhs.systemConfigurationId
    }
  }

  struct ProfileEntryIterationId: Hashable, Codable {
    let profileEntryId : ProfileEntryId
    let iteration      : Iteration
    var hashValue: Int {
       return profileEntryId.hashValue ^ (iteration &* 16777619)
    }
    static func == (lhs: ProfileEntryIterationId, rhs: ProfileEntryIterationId) -> Bool {
      return 
        lhs.profileEntryId == rhs.profileEntryId && 
        lhs.iteration      == rhs.iteration
    }
  }

  struct TimeAndEnergyDelta: Hashable, Codable {
    let timeDelta : Double
    let energyDelta : Double
    var hashValue: Int {
       return timeDelta.hashValue ^ (energyDelta.hashValue &* 16777619)
    }
    static func == (lhs: TimeAndEnergyDelta, rhs: TimeAndEnergyDelta) -> Bool {
      return 
        lhs.timeDelta   == rhs.timeDelta && 
        lhs.energyDelta == rhs.energyDelta
    }
  }

  // Representation of the output of a single execution of `make trace`
  struct Dicts: Codable {
    let applicationName                     : ApplicationName
    let architectureName                    : ArchitectureName
    let inputStreamName                     : ApplicationInputStreamName
    let getCurrentAppConfigurationIdDict    : [ KnobSettings : ApplicationConfigurationId ]
    let getCurrentSysConfigurationIdDict    : [ KnobSettings : SystemConfigurationId ]
    let warmupInputs                        : Int
    let numberOfInputsTraced                : Int
    let tracedConfigurations                : [ ProfileEntryId ]
    let tapeNoise                           : Double
    let applicationId                       : ApplicationId
    let timeOutlier                         : TimeOutlier
    let energyOutlier                       : EnergyOutlier
    let applicatioInputStreamId             : ApplicationInputStreamId
    let readDeltaDict                       : [ ProfileEntryIterationId : TimeAndEnergyDelta ]
  }

  // Database dictionaries
  private let database: Dicts

  private let appConfigurationIdToKnobSettings: [ ApplicationConfigurationId : KnobSettings ]
  private let sysConfigurationIdToKnobSettings: [ SystemConfigurationId      : KnobSettings ]

  public init?(databaseFile: String) {

    let databaseFileNameParts = databaseFile.split(separator: ".")
    let databaseFileNamePrefix = databaseFileNameParts.dropLast().joined(separator: ".")
    guard 
      databaseFileNameParts.last == "json",
      let databaseFileType = databaseFileNameParts.last,
      let databaseString = readFile(withName: databaseFileNamePrefix, ofType: "\(databaseFileType)"),
      let jsonData = databaseString.data(using: .utf8)
    else {
      Log.error("Could not read emulation database JSON from file : \(databaseFile).")
      fatalError()
    }
    guard
      let decodedDatabase = try? JSONDecoder().decode(Dicts.self, from: jsonData)
    else {
      Log.error("Could not decode emulation database from file '\(databaseString)' contents: \(jsonData).")
      fatalError()
    }
    
    self.database = decodedDatabase

    Log.info("Initialized emulation database from file '\(databaseFile)'.")

    self.appConfigurationIdToKnobSettings = Dictionary(decodedDatabase.getCurrentAppConfigurationIdDict.map{ ($1,$0) })
    self.sysConfigurationIdToKnobSettings = Dictionary(decodedDatabase.getCurrentSysConfigurationIdDict.map{ ($1,$0) })

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

  static func unwrapKnobStatus(knobStatus: [String : Any]) -> [String : Any] {
    return Dictionary(Array(knobStatus.map{ (knobName: String, knobValueAny: Any) in 
        let knobValueDict = knobValueAny as! [String : Any]
        let knobValue: Any = knobValueDict["value"]!
        return (knobName, knobValue)
    }))
  }

  /** Get the configuration Id of the current application knobs and their corresponding values from the database. 
  */
  private func getCurrentConfigurationId(knobType: String, knobStatus: [String : Any], _ currentConfigurationIdDict: [KnobSettings: Int]) -> Int {

    let knobsStatusAsKnobSettings = KnobSettings(kid: -1, DictDatabase.unwrapKnobStatus(knobStatus: knobStatus)) // -1 is a dummy value, since that id refers to the profiling table, which is irrelevant here

    guard let result = currentConfigurationIdDict[knobsStatusAsKnobSettings] else {
      fatalError("No entry in getCurrent\(knobType)ConfigurationIdDict dictionary database for the current \(knobType) configuration ID: \(knobsStatusAsKnobSettings)")
    }

    return result

  }

  /** Get the configuration Id of the current application knobs and their corresponding values from the database. 
  */
  public func getCurrentConfigurationId(application: Application) -> Int {

    let appKnobStatus = application.subModules["applicationKnobs"]!.getStatus()!

    return getCurrentConfigurationId(knobType: "App", knobStatus: appKnobStatus, database.getCurrentAppConfigurationIdDict)

  }

  /** Get the configuration Id of the current system knobs and their corresponding values from the database. 
  */
  public func getCurrentConfigurationId(architecture: Architecture) -> Int {

    let sysKnobStatus = architecture.subModules["systemConfigurationKnobs"]!.getStatus()!

    return getCurrentConfigurationId(knobType: "Sys", knobStatus: sysKnobStatus, database.getCurrentSysConfigurationIdDict)

  }

  /** Read the number of warmupInputs */
  func getWarmupInputs(application: String) -> Int {
    assert(application == database.applicationName)

    return database.warmupInputs
    
  }

  /** Get number of inputs profiled 
  *  Obtain the number of taped inputs
  *  NOTE Assumes that the profile entry (app/sys configurations and input)
  *       is present among the traced configurations.
  */
  func getNumberOfInputsProfiled( application: String, 
                                  architecture: String, 
                                  appCfg applicationConfigurationID: Int, 
                                  appInp applicationInputID: Int, 
                                  sysCfg systemConfigurationID: Int) -> Int {
    assert(architecture == database.architectureName)
    assert(application == database.applicationName)

    let profileEntryId = 
      ProfileEntryId( applicationConfigurationId : applicationConfigurationID
                    , applicationInputId         : applicationInputID
                    , systemConfigurationId      : systemConfigurationID
                    )

    if database.tracedConfigurations.contains(profileEntryId) {
      return database.numberOfInputsTraced
    }
    else {
      Log.error("Attempt to count the number of traced inputs for a configuration '\(profileEntryId)' that was not traced. The \(database.tracedConfigurations.count) traced configurations are: \(database.tracedConfigurations).")
      fatalError()
    }
    

  }

  /** Obtain the Tape noise*/
  func getTapeNoise(application: String) -> Double {
    assert(application == database.applicationName)

    return database.tapeNoise
  }

  /** Get the application id for a given application name from the database
  */
  public func getApplicationId(application: String) -> Int {
    assert(application == database.applicationName)

    return database.applicationId
  }

  /** Insert a knob of an application identified by its ID into a database.
  */
  public func insertKnob(applicationId: Int, knobName: String, knobType: String, referenceValue: String) {
    // TODO
  }

  /** Obtain outliers (timeOutlier, energyOutlier) for the application */
  func obtainOutliers(application: String) -> (Double, Double) {

    return (database.timeOutlier, database.energyOutlier)

  }

  /** An ApplicationInputStream Id is uniquely determined by an application name
  * and an input stream name.
  */
  public func getApplicatioInputStreamId(application: String, // name of application
                                  inputStream: String  // name of input stream
                                  ) -> Int {
    assert(application == database.applicationName && inputStream == database.inputStreamName)
    
    return database.applicatioInputStreamId

  }

  /** Read Delta from the JSON Database */
  public func readDelta(application: String, 
                architecture: String, 
                appCfg applicationConfigurationID: Int, 
                appInp applicationInputID: Int, 
                sysCfg systemConfigurationID: Int, 
                processing progressCounter: Int) 
                    ->
                (Double, Double) {

    let rescaleFactorMean     = 1.0
    var rescaleFactorVariance = 1.0

    let warmupInputs = getWarmupInputs(application: application)

    let numberOfInputsProfiled = getNumberOfInputsProfiled(application: application, architecture: architecture, appCfg: applicationConfigurationID, appInp: applicationInputID, sysCfg: systemConfigurationID)
    let maximalInputId = numberOfInputsProfiled - 1

    let profileEntryId = 
      ProfileEntryId( applicationConfigurationId : applicationConfigurationID
                    , applicationInputId         : applicationInputID
                    , systemConfigurationId      : systemConfigurationID
                    ) 

    Log.debug("Database.readDelta. Reading deltas for configuration with application knob settings: \(appConfigurationIdToKnobSettings[applicationConfigurationID]) and system knob settings: \(sysConfigurationIdToKnobSettings[systemConfigurationID]).")

    // This is the iteration, but modified to simulate iterations beyond the number that was actually traced
    let remappedIteration = getInputNumberToRead(inputID: progressCounter, maximalInputID: maximalInputId, warmupInputs: warmupInputs)

    // Differentiate between reading modes
    switch databaseKnobs.readingMode.get() {

      case ReadingMode.Tape:
        // Read the tape

        let profileEntryIterationId = ProfileEntryIterationId(profileEntryId : profileEntryId, iteration: remappedIteration) 
        
        let readDeltas = database.readDeltaDict[profileEntryIterationId]!

        let tapeNoise = getTapeNoise(application: application)

        // Adding noise
        let deltas =  ( readDeltas.timeDelta   + randomizerWhiteGaussianNoise(deviation: readDeltas.timeDelta   * tapeNoise)
                      , readDeltas.energyDelta + randomizerWhiteGaussianNoise(deviation: readDeltas.energyDelta * tapeNoise) )
        Log.debug("Database.readDelta with (Tape) for \(profileEntryIterationId) from emulation database: \((readDeltas.timeDelta,readDeltas.energyDelta)). With (Tape) noise included they are: \(deltas).")        

        return deltas

      case ReadingMode.Statistics:
        // Obtain the means and deviations of deltaEnergy and deltaTime

        // FIXME : Re-implement support for warmup iterations > 0 (fixed to 0 in Database.getInputNumberToRead)
        // FIXME : Double-check if we should use maximalInputId or maximalInputId-1 when computing variance
        let allDeltasForThisProfileEntry: [TimeAndEnergyDelta] = 
          Array((0 ..< maximalInputId).map{ (iteration: Int) in
            let profileEntryIterationId = ProfileEntryIterationId(profileEntryId : profileEntryId, iteration: iteration) 
            return database.readDeltaDict[profileEntryIterationId]!
          })
        let timeDeltasForThisProfileEntry   = allDeltasForThisProfileEntry.map{ $0.timeDelta   }
        let energyDeltasForThisProfileEntry = allDeltasForThisProfileEntry.map{ $0.energyDelta }

        let meanDeltaTime       : Double = timeDeltasForThisProfileEntry.reduce(  0.0, +) / Double(maximalInputId)
        let meanDeltaEnergy     : Double = energyDeltasForThisProfileEntry.reduce(0.0, +) / Double(maximalInputId)

        let varianceDeltaTime   : Double = timeDeltasForThisProfileEntry.map{   pow($0 - meanDeltaTime,   2.0) }.reduce(0.0, +) / Double(maximalInputId)
        let varianceDeltaEnergy : Double = energyDeltasForThisProfileEntry.map{ pow($0 - meanDeltaEnergy, 2.0) }.reduce(0.0, +) / Double(maximalInputId)

        let deviationDeltaTime  : Double = sqrt(varianceDeltaTime)
        let deviationDeltaEnergy: Double = sqrt(varianceDeltaEnergy)

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
        Log.debug("Database.readDelta with (Statistics) for \(profileEntryId) and iteration \(progressCounter): meanDeltaTime(\(meanDeltaTime)) deviationDeltaTime(\(deviationDeltaTime)) meanDeltaEnergy(\(meanDeltaEnergy)) deviationDeltaEnergy(\(deviationDeltaEnergy)) rescaleFactorMean(\(rescaleFactorMean)) rescaleFactorVariance(\(rescaleFactorVariance)) maximalInputId(\(maximalInputId)).")

        let n = 3.0
        let deltaTimeNoise   = rand(min: -meanDeltaTime,   max: meanDeltaTime  ) / n
        let deltaEnergyNoise = rand(min: -meanDeltaEnergy, max: meanDeltaEnergy) / n
        
        Log.debug("Database.readDelta n = \(n) deltaTimeNoise = \(deltaTimeNoise) deltaEnergyNoise = \(deltaEnergyNoise) ")
    
        let deltas = ( meanDeltaTime   * rescaleFactorMean + deltaTimeNoise
                     , meanDeltaEnergy * rescaleFactorMean + deltaEnergyNoise )
        
        Log.debug("Database.readDelta get deltas with noises from emulation database: \(deltas).")        

        return deltas
    }
  }

//-------------------------------

}