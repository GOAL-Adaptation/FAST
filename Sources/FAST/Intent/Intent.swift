/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Representation of an intent specification
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import LoggerAPI
import FASTController

//---------------------------------------

public protocol IntentSpec {


  var name: String { get }

  var knobs: [String : ([Any], Any)]  { get }

  var measures: [String]  { get }

  var constraint: Double { get }

  var constraintName: String { get }

  var costOrValue: ([Double]) -> Double { get }

  var optimizationType: FASTControllerOptimizationType  { get }

  var trainingSet: [String]  { get }

  var objectiveFunctionRawString: String? { get }

}

extension IntentSpec {
  var objectiveFunctionRawString: String? { return nil }

  /** All possbile knob settings. */
  func knobSpace(exhaustive: Bool = true) -> [KnobSettings] {
    func getKnobValues(for name: String) -> [Any] {
      let (exhaustiveKnobValues, _) = knobs[name]!
      var knobValues = exhaustiveKnobValues
      if !exhaustive, let leftEndKnobValue = knobValues.first, let rightEndKnobValue = knobValues.last {
        knobValues = exhaustiveKnobValues.count > 1 ? [leftEndKnobValue, rightEndKnobValue] : [rightEndKnobValue]
      }
      return knobValues
    }

    /** Builds up the space by extending it with the elements of
     *  successive elements of remainingKnobs. */
     func build(space: [[String : Any]], remainingKnobs: [String]) -> [[String : Any]] {
      if remainingKnobs.isEmpty {
        return space
      }
      else {
        let knobName = remainingKnobs.first!
        let knobValues = getKnobValues(for: knobName)
        var extendedSpace = [[String : Any]]()
        for knobValue in knobValues {
          for partialConfiguration in space {
            var extendedPartialConfiguration = [String : Any]()
            for (kn,kv) in partialConfiguration {
              extendedPartialConfiguration[kn] = kv
            }
            extendedPartialConfiguration[knobName] = knobValue
            extendedSpace.append(extendedPartialConfiguration)
          }
        }
        return build(space: extendedSpace, remainingKnobs: Array(remainingKnobs.dropFirst(1)))
      }
    }
    let knobNames = Array(knobs.keys).sorted()
    if knobNames.isEmpty {
        return []
    }
    else {
        let firstKnobName = knobNames.first!
        let firstKnobValues = getKnobValues(for: firstKnobName)
        let spaceWithFirstKnobsValuesOnly = firstKnobValues.map{ [firstKnobName: $0] }
        return build( space: spaceWithFirstKnobsValuesOnly
                    , remainingKnobs: Array(knobNames.dropFirst(1))
                    ).map{
                        // FIXME Eliminate undefined-value representations (-1 and [:]) below
                        //       by making the runtime.controller optional.
                        KnobSettings(kid: -1, $0)
                    }
    }

  }

  /**
   * JSON serializable dictionary that of:
   * - Knob names, ranges and reference values
   * - Measure names
   * - Current state of the intent components:
   *   - optimization type
   *   - objective function
   *   - constraint variable
   *   - constraint value
   */
  func toJson(runtime: Runtime) -> [String : Any] {

    let knobsJson =
        Array(knobs.map{ (name: String, rangeAndReferenceValue: ([Any],Any)) in
            [
                "name"           : name,
                "range"          : rangeAndReferenceValue.0,
                "referenceValue" : rangeAndReferenceValue.1
            ]
        })

    let measuresJson =
        Array(measures.map{ name in [ "name" : name ] })

    var intentJson: [String : Any] = [
        "name"               : name,
        "optimizationType"   : optimizationType == .minimize ? "min" : "max",
        "constraintVariable" : constraintName,
        "constraintValue"    : constraint
    ]

    // If the current objective function value is not Double.nan, insert a property for it into the JSON object.
    if let objectiveFunction = currentCostOrValue(runtime: runtime),
       !objectiveFunction.isNaN {
        intentJson["objectiveFunction"] = objectiveFunction
    }

    return [
        "knobs"    : knobsJson,
        "measures" : measuresJson,
        "intent"   : intentJson
    ]

  }

  /** If a model is loaded for this intent, compute the current measure window averages
      as an array in the same order as the array returned by measures(). */
  func measureWindowAverages(runtime: Runtime) -> [Double]? {
    if let model = runtime.models[name] {
        guard let measuringDevice = runtime.measuringDevices[name] else {
            FAST.fatalError("No measuring device registered for intent \(name).")
        }
        let measureValuesDict = measuringDevice.windowAverages()
        // FIXME Replace global measure store with custom ordered collection that avoids this conversion
        // FIXME This code duplicates code in Controller.swift. Generalize both when doing the above.
        var measureValueArray = [Double]()
        for measureName in self.measures {
            if let v = measureValuesDict[measureName] {
                if model.measureNames.contains(measureName) {
                  measureValueArray.append(v)
                }
                else {
                  FAST.fatalError("Measure '\(measureName)', present in intent, but not in model.")
                }
            }
            else {
                FAST.fatalError("Measure '\(measureName)', present in intent, has not been registered in the application.")
            }
        }
        return measureValueArray
    }
    else {
        return nil
    }
  }

  /** Objective function evaluated in the current measure window averages. */
  func currentCostOrValue(runtime: Runtime) -> Double? {
    return measureWindowAverages(runtime: runtime).map({ costOrValue($0) })
  }

  func isEverythingExceptConstraitValueIdentical(to spec: IntentSpec?) -> Bool {
    guard let other = spec else { return false }
    guard
      Set(measures) == Set(other.measures), // measures
      knobs.count == other.knobs.count, Set(knobs.keys) == Set(other.knobs.keys), // knobs
      objectiveFunctionRawString == other.objectiveFunctionRawString, // objective function
      optimizationType == other.optimizationType, // optimization type
      constraintName == other.constraintName // constraint name
    else { return false }
    for key in knobs.keys {
      if
        let values = knobs[key]?.0 as? [Int], let refValue = knobs[key]?.1 as? Int,
        let otherValues = other.knobs[key]?.0 as? [Int], let otherRefValue = other.knobs[key]?.1 as? Int
      {
        guard values == otherValues && refValue == otherRefValue else { return false }
      } else if
        let values = knobs[key]?.0 as? [Double], let refValue = knobs[key]?.1 as? Double,
        let otherValues = other.knobs[key]?.0 as? [Double], let otherRefValue = other.knobs[key]?.1 as? Double
      {
        guard values == otherValues && refValue == otherRefValue else { return false }
      } else {
        return false
      }
    }
    return true
  }

  // Used by application running in NonAdpative mode to initialze the KnobSettings for the ConstantController
  func referenceKnobSettings() -> KnobSettings {
    return KnobSettings(kid: -1, Dictionary(self.knobs.map{ 
      (knobName: String, rangeAndReferenceValue: ([Any], Any)) in 
      (knobName, rangeAndReferenceValue.1)
    }))
  }

}
