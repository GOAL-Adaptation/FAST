/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *  pemu: Database driven emulator
 *
 *        Emulator Tools
 *
 *  author: Ferenc A Bartha
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 */

//-------------------------------

import Foundation

//-------------------------------

/**
 *  Randomization-Specific Section
 */

/** Initialize the random generators */
func randomizerInit(seed: UInt64?) {
    if seed != nil {
        let _ = randi(seed: seed)
        let _ = rand(seed: seed)
    }
}

/** White Gaussian Noise */
func randomizerWhiteGaussianNoise(deviation standardDeviation: Double) -> Double {

  let x = rand(min: 0, max: 1)
  let y = rand(min: 0, max: 1)
  let z = sqrt(-2.0 * log(x)) * cos(2.0 * 3.14159 * y)
  return standardDeviation * z

}

/** Eliminate outliers that arise due to erratic measurements that result in negative measurement emulation */
func randomizerEliminateOutliers(measurement: Double, error: Double, factor: inout Double, safetyMargin: Double) -> () {
  factor = (error == 0) ? factor : min(factor, measurement / (error * safetyMargin) )
}

//-------------------------------
