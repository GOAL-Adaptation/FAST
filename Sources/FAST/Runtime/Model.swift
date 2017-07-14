import FASTController
import CSwiftV
import LoggerAPI

struct Configuration {
    public let id: Int // FIXME: Eliminate this by making Configuration Equatable
    public let knobSettings: KnobSettings
    public let measureValues: [Double]
    public let measureNames: [String]

    init(_ id: Int, _ knobSettings: KnobSettings, _ measures: [String : Double]) {
        self.id = id
        self.knobSettings = knobSettings
        measureNames = measures.keys.sorted()
        measureValues = measureNames.map{ measures[$0]! }
    }

    private init(_ id: Int, _ knobSettings: KnobSettings, _ measureValues: [Double], _ measureNames: [String]) {
        self.id = id
        self.knobSettings = knobSettings
        self.measureValues = measureValues
        self.measureNames = measureNames
    }

    // FIXME: Eliminate this by making Configuration Equatable
    func with(newId: Int) -> Configuration {
        return Configuration(newId, knobSettings, measureValues, measureNames)
    }
}

open class Model {

    private let configurations: [Configuration]
    public let initialConfigurationIndex: Int?
    public let measureNames: [String]?

    public var isEmpty: Bool {
        get {
            return configurations.isEmpty
        }
    }

    init() {
        configurations = []
        initialConfigurationIndex = nil
        measureNames = nil
    }

    /** Loads a model, consisting of two tables for knob- and measure values.
        The entries in these tables are assumed to be connected by an "id" column,
        that is, the number of rows in each table must match. */
    public init(_ knobCSV: String, _ measureCSV: String, _ initialConfigurationIndex: Int = 0) {
        let knobTable = CSwiftV(with: knobCSV)
        let measureTable = CSwiftV(with: measureCSV)
        assert(knobTable.rows.count == measureTable.rows.count, "number of rows in knob and measure config files must match")
        let knobNames = Array(knobTable.headers.dropFirst())
        self.measureNames = Array(measureTable.headers.dropFirst())
        let parseKnobSetting = { (setting: String) -> Any in
            // TODO Add support for other knob types, based on type information in intent spec, and error handling
            if let i = Int(setting) {
                return i
            } 
            if let d = Double(setting) {
                return d
            }
            return setting
        }
        var configurations: [Configuration] = []      
        for configId in 0 ..< knobTable.rows.count {
            let knobNameValuePairs = Array(zip(knobNames, knobTable.rows[configId].dropFirst().map{ parseKnobSetting($0) }))
            let knobSettings = KnobSettings([String:Any](elements: knobNameValuePairs))
            let measureNameValuePairs = Array(zip(measureNames!, measureTable.rows[configId].dropFirst().map{ Double($0)! })) // FIXME Add error handling
            let measures = [String:Double](elements: measureNameValuePairs)
            configurations.append(Configuration(configId, knobSettings, measures))
        }
        self.configurations = configurations
        self.initialConfigurationIndex = initialConfigurationIndex
        Log.exit("Initialized model.")
    }

    internal init(_ configurations: [Configuration], _ initialConfigurationIndex: Int) {
        assert(!configurations.isEmpty || (configurations.isEmpty && initialConfigurationIndex == -1))
        measureNames = configurations.first!.measureNames
        self.configurations = configurations
        assert(0 <= initialConfigurationIndex && initialConfigurationIndex < configurations.count, "0  <= initialCondigurationIndex < |configurations|")
        self.initialConfigurationIndex = initialConfigurationIndex
        assert(configurations.reduce(true, { $0 && self.measureNames! == $1.measureNames }), "measure names must be the same for all configurations")
    }

    private init(_ configurations: [Configuration], _ initialConfigurationIndex: Int?, _ measureNames: [String]?) {
        self.configurations = configurations
        self.initialConfigurationIndex = initialConfigurationIndex
        self.measureNames = measureNames
    }

    subscript(_ index: Int) -> Configuration {
        get {
            return configurations[index]
        }
    }

    func getInitialConfiguration() -> Configuration? {
        return configurations[initialConfigurationIndex!] // FIXME propagate nil
    }
    
    func getFASTControllerModel() -> FASTControllerModel {
        return FASTControllerModel(measures: configurations.map{ $0.measureValues })
    }

    /** Make a Model based on this one, but whose configurations are sorted by their values for the given measure. */
    func sorted(by measureName: String) -> Model {
        if self.isEmpty {
            return self
        }
        assert(measureNames!.contains(measureName), "invalid measure name \"\(measureName)\"")
        let measureIndex = measureNames!.index(of: measureName)!
        let sortedConfigurations = configurations.sorted(by: { (l: Configuration, r: Configuration) in 
            l.measureValues[measureIndex] < r.measureValues[measureIndex] 
        })
        var sortedConfigurationsWithUpdatedIds: [Configuration] = []
        for configId in 0 ..< sortedConfigurations.count {
            sortedConfigurationsWithUpdatedIds.append(sortedConfigurations[configId].with(newId: configId))
        }
        if let i = initialConfigurationIndex {
            let updatedInitialConfigurationIndex = sortedConfigurations.index(where: { $0.id == i })
            return Model(sortedConfigurations, updatedInitialConfigurationIndex, measureNames)
        }
        else {
            return Model(sortedConfigurations, nil, measureNames)
        }
    }

}