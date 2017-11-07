/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Tests of the Statistics class
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import Dispatch
import XCTest
@testable import FAST

//---------------------------------------

class StatisticsTest: FASTTestCase {

    /** Test computing the window average of a measure */
    func testWindowAverages() {        
        let s = Statistics(measure: "s", windowSize: 3)
        s.observe(2.0)
        XCTAssertEqual(2.0, s.windowAverage)
        s.observe(4.0)
        XCTAssertEqual(3.0, s.windowAverage)
        s.observe(6.0)
        XCTAssertEqual(4.0, s.windowAverage)
        s.observe(8.0)
        XCTAssertEqual(6.0, s.windowAverage)
        s.observe(10.0)
        XCTAssertEqual(8.0, s.windowAverage)
    }

    static var allTests = [
        ("testWindowAverages", testWindowAverages)
    ]

}

