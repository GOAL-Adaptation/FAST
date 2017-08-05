/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Example application: Incrementer
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import Foundation
import HeliumLogger
import LoggerAPI
import FASTController
import FAST

//---------------------------------------

HeliumLogger.use(.entry)

// Initialize FAST

let window: UInt32 = 20

// Application

let threshold = Knob("threshold", 10000000)
let step = Knob("step", 1)

var x = 0

optimize("incrementer", across: window, ["latency", "operations"]) {
    let start = NSDate().timeIntervalSince1970
    var operations = 0.0
    while(x < threshold.get()) {
        x += step.get()
        operations += 1
    }
    x = 0
    let latency = NSDate().timeIntervalSince1970 - start
    Runtime.measure("latency", latency)
    Runtime.measure("operations", operations)
}


