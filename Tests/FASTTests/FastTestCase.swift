/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Base test case that resets the Runtime state before and after each run.
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import XCTest
@testable import FAST

//---------------------------------------

class FASTTestCase : XCTestCase {
    var runtime = Runtime.newRuntime()
    let windowSize: UInt32 = 40

    /** Note: When overriding this, remember to call super.setUp(). */
    override func setUp() {
        runtime = Runtime.newRuntime()
        runtime.measure("time", 0.0)
        runtime.measure("systemEnergy", 0.0)
        runtime.resetRuntimeMeasures(windowSize: windowSize)
    }

    override func tearDown() {
        runtime = Runtime.newRuntime()
    }
}
