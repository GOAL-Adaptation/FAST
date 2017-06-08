/**

  Representation of an intent specification.

*/

import FASTController

public protocol IntentSpec {

  // knobs       k = 1 ..< 30               reference 1
  //             l = [ "a", "b", "c", "d" ] reference "b"
  // measures    p: Double
  //             q: Double 
  //             r: Double 
  // intent      max(q/r) such that p == 20 
  // trainingSet { "input1.dat --someFlag=true", "input2.dat" }

  var name: String { get }

  var knobs: [String : ([Any], Any)]  { get }
  
  var measures: [String]  { get }

  var constraint: Double { get }

  var constraintName: String { get }

  var costOrValue: ([Double]) -> Double { get }

  var optimizationType: FASTControllerOptimizationType  { get }

  var trainingSet: [String]  { get }

}