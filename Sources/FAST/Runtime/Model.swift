import FASTController
import CSwiftV

struct Configuration {
    public let knobSettings: KnobSettings
    public let measureValues: [Double]
    public let measureNames: [String]

    init(_ knobSettings: KnobSettings, _ measures: [String : Double]) {
        self.knobSettings = knobSettings
        measureNames = measures.keys.sorted()
        measureValues = measureNames.map{ measures[$0]! }
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
            configurations.append(Configuration(knobSettings, measures))
        }
        self.configurations = configurations
        self.initialConfigurationIndex = initialConfigurationIndex
    }

    internal init(_ configurations: [Configuration], _ initialConfigurationIndex: Int) {
        assert(!configurations.isEmpty || (configurations.isEmpty && initialConfigurationIndex == -1))
        measureNames = configurations.first!.measureNames
        self.configurations = configurations
        assert(0 <= initialConfigurationIndex && initialConfigurationIndex < configurations.count, "0  <= initialCondigurationIndex < |configurations|")
        self.initialConfigurationIndex = initialConfigurationIndex
        assert(configurations.reduce(true, { $0 && self.measureNames! == $1.measureNames }), "measure names must be the same for all configurations")
        print("configurations: \(configurations)")
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

}