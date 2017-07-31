/**

  Representation of an intent specification.

*/

import FASTController

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
                    ).map{ KnobSettings($0) } 
    }

  }

}