import LoggerAPI

/** Initialization Parameters */
struct InitializationParameters {
    enum ArchitectureName {
        case ArmBigLittle, XilinxZcu
    }

    enum ApplicationName {
        case radar, x264, capsule, incrementer, flightTestScenario7
    }

    let architecture             : ArchitectureName
    let applicationName          : ApplicationName
    let applicationInputFileName : String
    let adaptationEnabled        : Bool
    let statusInterval           : UInt64
    let randomSeed               : UInt64
    let model                    : Model?
    let initialConditions        : Perturbation

    init?(json: [String: Any]) {
        guard let architecture             = extract(type: ArchitectureName.self, name: "architecture"           , json: json) else 
        {   FAST.fatalError("Unable to parse InitializationParameters (architecture) from JSON: \(json).") }
        guard let applicationJson          = json["application"] as? [String : Any] else 
        {   FAST.fatalError("Unable to parse InitializationParameters (application) from JSON: \(json).") }
        guard let applicationName          = extract(type: ApplicationName.self , name: "applicationName"        , json: applicationJson) else 
        {   FAST.fatalError("Unable to parse InitializationParameters (applicationName) from JSON: \(json).") }
        guard let applicationInputFileName = extract(type: String.self          , name: "inputFileName"          , json: applicationJson) else 
        {   FAST.fatalError("Unable to parse InitializationParameters (inputFileName) from JSON: \(json).") }
        guard let adaptationEnabled        = extract(type: Bool.self            , name: "adaptationEnabled"      , json: json) else 
        {   FAST.fatalError("Unable to parse InitializationParameters (adaptationEnabled) from JSON: \(json).") }
        guard let statusInterval           = extract(type: UInt64.self          , name: "statusInterval"         , json: json) else 
        {   FAST.fatalError("Unable to parse InitializationParameters (statusInterval) from JSON: \(json).") }
        guard let randomSeed               = extract(type: UInt64.self          , name: "randomSeed"             , json: json) else 
        {   FAST.fatalError("Unable to parse InitializationParameters (randomSeed) from JSON: \(json).") }
        guard let initialConditionsJson    = json["initialConditions"] as? [String : Any] else 
        {   FAST.fatalError("Unable to parse InitializationParameters (initialConditions) from JSON: \(json).") }
        guard let initialConditions        = Perturbation(json: initialConditionsJson) else 
        {   FAST.fatalError("Unable to parse InitializationParameters (Perturbation) from JSON: \(json).") }

        if String(describing: applicationName) != initialConditions.missionIntent.name {
            Log.error("Intent name '\(initialConditions.missionIntent.name)' differs from application name: '\(applicationName)'.")
            return nil
        }

        if 
            let measureTableAny = json["measureTable"],
            let knobTableAny    = json["knobTable"],
            let measureTable    = measureTableAny as? String,
            let knobTable       = knobTableAny    as? String
        {
            self.model = Model(knobTable, measureTable, initialConditions.missionIntent)
        }
        else {
            self.model = nil
        }

        self.architecture             = architecture
        self.applicationName          = applicationName
        self.applicationInputFileName = applicationInputFileName
        self.adaptationEnabled        = adaptationEnabled
        self.statusInterval           = statusInterval
        self.randomSeed               = randomSeed
        
        self.initialConditions        = initialConditions

    }

    func asDict() -> [String : Any] {
        return 
            [ "architecture"             : self.architecture
            , "applicationName"          : self.applicationName
            , "applicationInputFileName" : self.applicationInputFileName
            , "adaptationEnabled"        : self.adaptationEnabled
            , "statusInterval"           : self.statusInterval
            , "randomSeed"               : self.randomSeed
            , "initialConditions"        : self.initialConditions.asDict()
            ]
    }

}
