/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Example application: Incrementer
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import Foundation
import FAST

let threshold = Knob("threshold", 200000)
let step = Knob("step", "1")

var x = 0
optimize("incrementer", [threshold, step]) {
    var operations = 0.0
    while(x < threshold.get()) {
        x += Int(step.get())!
        operations += 1
    }
    x = 0
    measure("operations", operations)
    measure("quality", 1.0 / Double(step.get())!)
}
