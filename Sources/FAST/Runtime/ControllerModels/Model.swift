/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Model used by controller to compute schedules.
 *
 *        Relates knob values with measure values. When the FASTController
 *        is initialized, this is converted into a FASTControllerModel that,
 *        in contrast, relates knob values with a cost-or-value quantity
 *        (computed from knobs using the objective function of the active
 *        intent) and a constraint quantity.
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import FASTController
import CSwiftV
import LoggerAPI

//---------------------------------------

/* A list of configurations. */
open class Model {

    internal let configurations: [Configuration]
    public let initialConfigurationIndex: Int?
    public let measureNames: [String]

    /** Loads a model, consisting of two tables for knob- and measure values.
        The entries in these tables are assumed to be connected by an "id" column,
        that is, the number of rows in each table must match. */
    public init(_ knobCSV: String, _ measureCSV: String, _ initialConfigurationIndex: Int = 0) {
        let knobTable = CSwiftV(with: knobCSV)
        let measureTable = CSwiftV(with: measureCSV)
        assert(knobTable.rows.count == measureTable.rows.count, "number of rows in knob and measure config files must match")
        let knobNames = Array(knobTable.headers.dropFirst())
        self.measureNames = Array(measureTable.headers.dropFirst())
        var configurations: [Configuration] = []
        for configId in 0 ..< knobTable.rows.count {
            let knobNameValuePairs = Array(zip(knobNames, knobTable.rows[configId].dropFirst().map{ parseKnobSetting(setting: $0) }))
            let knobSettings = KnobSettings(kid: configId, [String:Any](knobNameValuePairs))
            let measureNameValuePairs = Array(zip(measureNames, measureTable.rows[configId].dropFirst().map{ Double($0)! })) // FIXME Add error handling
            let measures = [String:Double](measureNameValuePairs)
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
        assert(configurations.reduce(true, { $0 && self.measureNames == $1.measureNames }), "measure names must be the same for all configurations")
    }

    private init(_ configurations: [Configuration], _ initialConfigurationIndex: Int?, _ measureNames: [String]) {
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
        assert(measureNames.contains(measureName), "invalid measure name \"\(measureName)\"")
        let measureIndex = measureNames.index(of: measureName)!
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
