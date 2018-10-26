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
    public let measureNames: [String]

    private let measureNameToIndexMap: [String: Int]

    /** Loads a model, consisting of two tables for knob- and measure values.
        The entries in these tables are assumed to be connected by an "id" column,
        that is, the number of rows in each table must match. */
    public init(_ knobCSV: String, _ measureCSV: String, _ intent: IntentSpec) {
        let knobTable = CSwiftV(with: knobCSV)
        let measureTable = CSwiftV(with: measureCSV)
        assert(knobTable.rows.count == measureTable.rows.count, "Number of rows in knob and measure config files must match")
        let knobNames = Array(knobTable.headers.dropFirst())
        let measureNonIdHeaders = measureTable.headers.dropFirst()
        self.measureNames = intent.measures
        self.measureNameToIndexMap = Dictionary(Array(zip(intent.measures, 0 ..< intent.measures.count)))
        assert(!intent.measures.map{ measureNonIdHeaders.contains($0) }.contains(false), "All measures in the intent must also be present in the model.")
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
        Log.exit("Initialized model.")
    }

    internal init(_ configurations: [Configuration]) {
        Log.debug("Initializing Model with configurations \(configurations).")
        assert(!configurations.isEmpty)
        measureNames = configurations.first!.measureNames
        self.measureNameToIndexMap = Dictionary(Array(zip(measureNames, 0 ..< measureNames.count)))
        self.configurations = configurations
        assert(configurations.reduce(true, { $0 && self.measureNames == $1.measureNames }), "measure names must be the same for all configurations")
    }

    private init(_ configurations: [Configuration], _ measureNames: [String]) {
        Log.debug("Initializing Model with measureNames \(measureNames), and configurations \(configurations).")
        self.configurations = configurations
        self.measureNames = measureNames
        self.measureNameToIndexMap = Dictionary(Array(zip(measureNames, 0 ..< measureNames.count)))
    }

    /** Get the configuration at the given index. */
    subscript(_ index: Int) -> Configuration {
        get {
            return configurations[index]
        }
    }

    /** Get the measure value of the configuration at the given index. */
    func getMeasureValue(_ index: Int, measureName: String) -> Double {
        return configurations[index].measureValues[measureNameToIndexMap[measureName]!]
    }

    func getFASTControllerModel() -> FASTControllerModel {
        return FASTControllerModel(measures: configurations.map{ $0.measureValues })
    }

    /** Make a Model based on this one, but whose configurations are sorted by their values for the given measure. */
    func sorted(by measureName: String) -> Model {
        assert(measureNames.contains(measureName), "invalid measure name \"\(measureName)\"")
        let measureIndex = measureNames.index(of: measureName)!
        let sortedConfigurationsWithOriginalIds = configurations.sorted(by: { (l: Configuration, r: Configuration) in
            l.measureValues[measureIndex] < r.measureValues[measureIndex]
        })
        var sortedConfigurationsWithUpdatedIds: [Configuration] = []
        for configId in 0 ..< sortedConfigurationsWithOriginalIds.count {
            sortedConfigurationsWithUpdatedIds.append(sortedConfigurationsWithOriginalIds[configId].with(newId: configId))
        }
        return Model(sortedConfigurationsWithUpdatedIds, measureNames)
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
                        FAST.fatalError("Knob \(knobName) in model has value '\(knobValue)' of unsupported type: '\(type(of: knobValue))'.")
                    }
                }
                else {
                    return true
                }
            }.reduce(true, { $0 && $1 })
        }
        
        return trim(toSatisfy: isInIntent, "shrink to intent spec with knobs: \(spec.knobs)")

    }

    /** Trim model to contain only configurations that satisfy the passed filter. */
    func trim(toSatisfy filter: (Configuration) -> Bool, _ filterDescription: String) -> Model {
        let filteredConfigurations = self.configurations.filter{ filter($0) }
        var filteredConfigurationsWithUpdatedIds: [Configuration] = []
        for configId in 0 ..< filteredConfigurations.count {
            filteredConfigurationsWithUpdatedIds.append(filteredConfigurations[configId].with(newId: configId))
        }
        if filteredConfigurationsWithUpdatedIds.count < self.configurations.count {
            Log.verbose("Trimmed controller model from \(self.configurations.count) to \(filteredConfigurationsWithUpdatedIds.count) configurations.")
        }
        return Model(filteredConfigurationsWithUpdatedIds, measureNames)
    }
    
    func toKnobTableCSV() -> String {
        let knobNames = Array(self.configurations[0].knobSettings.settings.keys).sorted()
        let header = knobNames.joined(separator: ",") + "\n"
        return header + self.configurations.map{ 
            $0.toKnobTableLine(knobNames: knobNames) 
        }.joined(separator: "\n")
    }

}
