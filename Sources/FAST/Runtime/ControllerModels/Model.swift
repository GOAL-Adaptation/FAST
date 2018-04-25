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
        let measureNonIdHeaders = measureTable.headers.dropFirst()
        self.measureNames = Array(measureNonIdHeaders).sorted()
        var configurations: [Configuration] = []
        for configId in 0 ..< knobTable.rows.count {
            let knobNameValuePairs = Array(zip(knobNames, knobTable.rows[configId].dropFirst().map{ parseKnobSetting(setting: $0) }))
            let knobSettings = KnobSettings(kid: configId, [String:Any](knobNameValuePairs))
            var measures = [String : Double]()
            for m in measureNames {
                let indexOfM = measureNonIdHeaders.index(of: m)! 
                measures[m] = Double(measureTable.rows[configId].dropFirst()[indexOfM])! // FIXME Add error handling
            }
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
        if let ici = initialConfigurationIndex {
            let updatedInitialConfigurationIndex = sortedConfigurations.index(where: { $0.id == ici })
            return Model(sortedConfigurations, updatedInitialConfigurationIndex, measureNames)
        }
        else {
            return Model(sortedConfigurations, nil, measureNames)
        }
    }

    /** Make a model basd on this one, but only containing configurations matching those in the intent. */
    func trim(to spec: IntentSpec) -> Model {

        func isInIntent(_ c: Configuration) -> Bool {
            return c.knobSettings.settings.map{ (knobName: String, knobValue: Any) in  
                if let (knobRange,_) = spec.knobs[knobName] {
                    if 
                        let v = knobValue as? Int,
                        let r = knobRange as? [Int] 
                    {
                        return r.contains(v)
                    } 
                    else {
                        Log.error("Knob \(knobName) in model has value '\(knobValue)' of unsupported type: '\(type(of: knobValue))'.")
                        fatalError()
                    }
                }
                else {
                    return true
                }
            }.reduce(true, { $0 && $1 })
        }
        
        let filteredConfigurations = self.configurations.filter{ isInIntent($0) }
        var filteredConfigurationsWithUpdatedIds: [Configuration] = []
        for configId in 0 ..< filteredConfigurations.count {
            filteredConfigurationsWithUpdatedIds.append(filteredConfigurations[configId].with(newId: configId))
        }
        if filteredConfigurationsWithUpdatedIds.count < self.configurations.count {
            Log.verbose("Trimmed controller model from \(self.configurations.count) to \(filteredConfigurationsWithUpdatedIds.count) configurations.")
        }
        
        if let ici = self.initialConfigurationIndex {
            if !isInIntent(self.configurations[ici]) {
                Log.warning("Initial configuration lost by shrinking to intent spec with knobs: \(spec.knobs). Using \(filteredConfigurations[0].knobSettings) instead.")
                return Model(filteredConfigurationsWithUpdatedIds, 0, measureNames)
            }
            else {
                let updatedInitialConfigurationIndex = self.configurations.index(where: { $0.id == ici })
                return Model(filteredConfigurationsWithUpdatedIds, updatedInitialConfigurationIndex, measureNames)
            }
        }
        else {
            return Model(filteredConfigurationsWithUpdatedIds, nil, measureNames)
        }

    }
    
    func toKnobTableCSV() -> String {
        let knobNames = Array(self.configurations[0].knobSettings.settings.keys).sorted()
        let header = knobNames.joined(separator: ",") + "\n"
        return header + self.configurations.map{ 
            $0.toKnobTableLine(knobNames: knobNames) 
        }.joined(separator: "\n")
            
    }

}
