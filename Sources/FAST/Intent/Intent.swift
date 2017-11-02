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

}

extension IntentSpec {

  /** All possbile knob settings. */ 
  func knobSpace() -> [KnobSettings] {
    /** Builds up the space by extending it with the elements of 
     *  successive elements of remainingKnobs. */
	func build(space: [[String : Any]], remainingKnobs: [String]) -> [[String : Any]] {
        if remainingKnobs.isEmpty {
            return space
        }
        else {
            let knobName = remainingKnobs.first!
            let (knobValues, _) = knobs[knobName]!
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
        let (firstKnobValues, _) = knobs[firstKnobName]!
        let spaceWithFirstKnobsValuesOnly = firstKnobValues.map{ [firstKnobName: $0] }
        return build( space: spaceWithFirstKnobsValuesOnly
                    , remainingKnobs: Array(knobNames.dropFirst(1))
                    ).map{ 
                        // FIXME Eliminate undefined-value representations (-1 and [:]) below
                        //       by making the Runtime.controller optional.
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
  func toJson() -> [String : Any] {

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
        "optimizationType"   : optimizationType,
        "constraintVariable" : constraintName,
        "constraintValue"    : constraint
    ]
    
    // If a model is loaded for this intent, compute the current objectiveFunction value
    // and insert a property for it into the JSON object
    if let model = Runtime.models[name] {
        guard let measuringDevice = Runtime.measuringDevices[name] else {
            Log.error("No measuring device registered for intent \(name).")
            fatalError()
        }
        let measureValuesDict = measuringDevice.windowAverages()
        // FIXME Replace global measure store with custom ordered collection that avoids this conversion
        // FIXME This code duplicates code in Controller.swift. Generalize both when doing the above.
        var measureValueArray = [Double]()
        for measureName in model.measureNames {
            if let v = measureValuesDict[measureName] {
                measureValueArray.append(v)
            }
            else {
                Log.error("Measure '\(measureName)', present in model, has not been registered in the application.")
                fatalError()
            }
        }
        intentJson["objectiveFunction"] = costOrValue(measureValueArray)
    }

    return [
        "knobs"    : knobsJson,
        "measures" : measuresJson,
        "intent"   : intentJson
    ]

  }

}