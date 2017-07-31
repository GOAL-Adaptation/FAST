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