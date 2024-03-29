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
        for rowNumber in 0 ..< knobTable.rows.count {
            let currentRow = knobTable.rows[rowNumber]
            if currentRow == knobTable.headers {
                FAST.fatalError("Repeated header line found on row \(rowNumber) in model.")
            }
            guard let configId = Int(currentRow.first!) else {
                FAST.fatalError("Row \(rowNumber) of model is empty.")
            }
            let knobNameValuePairs = Array(zip(knobNames, currentRow.dropFirst().map{ parseKnobSetting(setting: $0) }))
            let knobSettings = KnobSettings(kid: configId, [String:Any](knobNameValuePairs))
            var measures = [String : Double]()
            for m in measureNames {
                guard let indexOfM = measureNonIdHeaders.index(of: m) else {
                    FAST.fatalError("Measure '\(m)' not found in measure table.")
                }
                measures[m] = Double(measureTable.rows[rowNumber].dropFirst()[indexOfM])! // FIXME Add error handling
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

    /** Get the configuration with the corresponding KnobSettings */
    func getConfiguration(correspondingTo knobSettings: KnobSettings) -> Configuration {
        let matchingConfigurations = configurations.filter{ $0.knobSettings == knobSettings }
        switch matchingConfigurations.count {
            case 0:
                FAST.fatalError("No configuration with the following knob settings was found in the model: \(knobSettings).")
            case 1:
                return matchingConfigurations[0]
            default:
                FAST.fatalError("Multiple configurations (\(matchingConfigurations.map{ $0.id })) with the following knob settings were found in the model: \(knobSettings).")
        }        
    }
   
    func getSizeOfConfigurations() -> Int {return configurations.count}

	func getDomainArray() -> [UInt32] {
        return (configurations.map{UInt32($0.id)})
    }

    func getMeasureVectorFunction() -> (UInt32) -> [Double] {
        return {(id: UInt32) in self.configurations[Int(id)].measureValues}
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
        
        return trim(toSatisfy: { $0.isIn(intent: spec) }, "shrink to intent spec with knobs: \(spec.knobs)")

    }

    /** Trim model to contain only configurations that satisfy the passed filter. */
    func trim(toSatisfy filter: (Configuration) -> Bool, _ filterDescription: String) -> Model {
        let filteredConfigurations = self.configurations.filter{ filter($0) }
        if filteredConfigurations.count < self.configurations.count {
            Log.verbose("Trimmed controller model from \(self.configurations.count) to \(filteredConfigurations.count) configurations.")
        }
        else {
            Log.verbose("Controller model not affected by filter, no configurations trimmed.")
        }
        return Model(filteredConfigurations, measureNames)
    }
    
    func toKnobTableCSV() -> String {
        let knobNames = Array(self.configurations[0].knobSettings.settings.keys).sorted()
        let header = knobNames.joined(separator: ",") + "\n"
        return header + self.configurations.map{ 
            $0.toKnobTableLine(knobNames: knobNames) 
        }.joined(separator: "\n")
    }

    func range<T: Equatable>(ofKnob knobName: String) -> [T] {
        let rangeWithPossibleDuplicates: [T] = self.configurations.map { 
            configuration in 
            guard let knobValue = configuration.knobSettings.settings[knobName] else {
                FAST.fatalError("Configuration '\(configuration)' does not contain a value for knob '\(knobName)'. Can not compute knob range.")
            }
            guard let knobValueAsT = knobValue as? T else {
                FAST.fatalError("Knob value '\(knobValue)' for knob '\(knobName)' in configuration '\(configuration)' could not be cast to the expected type '\(T.self)'.")
            }
            return knobValueAsT
        }
        let range = rangeWithPossibleDuplicates.reduce([], {
            range, knobValue in
            return range.contains(knobValue) ? range : range + [knobValue]
        })
        return range
    }

}
