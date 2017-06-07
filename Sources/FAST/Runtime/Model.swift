import FASTController

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

class Model {

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

    init(_ configurations: [Configuration], _ initialConfigurationIndex: Int) {
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

    public func getInitialConfiguration() -> Configuration? {
        return configurations[initialConfigurationIndex!] // FIXME propagate nil
    }
    
    func getFASTControllerModel() -> FASTControllerModel {
        return FASTControllerModel(measures: configurations.map{ $0.measureValues })
    }

}