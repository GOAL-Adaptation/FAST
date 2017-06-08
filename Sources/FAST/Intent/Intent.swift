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

  func knobs() -> [String : ([Any], Any)]
  
  func measures() -> [String]

  func constraint() -> Double

  func constraintName() -> String

  func costOrValue() -> ([Double]) -> Double

  func optimizationType() -> FASTControllerOptimizationType

  func trainingSet() -> [String]

}