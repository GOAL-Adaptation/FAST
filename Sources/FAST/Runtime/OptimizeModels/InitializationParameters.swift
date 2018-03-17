import LoggerAPI

/** Initialization Parameters */
struct InitializationParameters {
    enum ArchitectureName {
        case ArmBigLittle, XilinxZcu
    }

    enum ApplicationName {
        case radar, x264, CaPSuLe, incrementer
    }

    let architecture             : ArchitectureName
    let applicationName          : ApplicationName
    let applicationInputFileName : String
    let missionLength            : UInt64?
    let energyLimit              : UInt64?
    let adaptationEnabled        : Bool
    let statusInterval           : UInt64
    let randomSeed               : UInt64
    let initialConditions        : Perturbation

    init?(json: [String: Any]) {
        if let architecture             = extract(type: ArchitectureName.self, name: "architecture"           , json: json)
         , let applicationJson          = json["application"] as? [String : Any]
         , let applicationName          = extract(type: ApplicationName.self , name: "applicationName"        , json: applicationJson)
         , let applicationInputFileName = extract(type: String.self          , name: "inputFileName"          , json: applicationJson)
         , let adaptationEnabled        = extract(type: Bool.self            , name: "adaptationEnabled"      , json: json)
         , let statusInterval           = extract(type: UInt64.self          , name: "statusInterval"         , json: json)
         , let randomSeed               = extract(type: UInt64.self          , name: "randomSeed"             , json: json)
         , let initialConditionsJson    = json["initialConditions"] as? [String : Any]
         , let initialConditions        = Perturbation(json: initialConditionsJson)
        {
            let missionLength = extract(type: UInt64.self                    , name: "missionLength"          , json: json)
            let energyLimit   = extract(type: UInt64.self                    , name: "energyLimit"            , json: json)

            if String(describing: applicationName) != initialConditions.missionIntent.name {
                Log.error("Intent name '\(initialConditions.missionIntent.name)' differs from application name: '\(applicationName)'.")
                return nil
            }

            self.architecture             = architecture
            self.applicationName          = applicationName
            self.applicationInputFileName = applicationInputFileName
            self.missionLength            = missionLength
            self.energyLimit              = energyLimit
            self.adaptationEnabled        = adaptationEnabled
            self.statusInterval           = statusInterval
            self.randomSeed               = randomSeed
            self.initialConditions        = initialConditions
        }
        else {
            Log.error("Unable to parse Perturbation from JSON: \(json).")
            return nil
        }
    }
}
