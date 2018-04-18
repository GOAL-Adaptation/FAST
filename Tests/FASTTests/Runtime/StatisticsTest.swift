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

    /** Test computing the total average of a measure */
    func testTotalAverage() {        
        let s = Statistics(measure: "s", windowSize: 3)
        XCTAssertTrue(s.totalAverage.isNaN)
        s.observe(2.0)
        XCTAssertEqual(2.0, s.totalAverage)
        s.observe(4.0)
        XCTAssertEqual(3.0, s.totalAverage)
        s.observe(6.0)
        XCTAssertEqual(4.0, s.totalAverage)
        s.observe(8.0)
        XCTAssertEqual(5.0, s.totalAverage)
        s.observe(10.0)
        XCTAssertEqual(6.0, s.totalAverage)
    }

    /** Test computing the total variance of a measure */
    func testTotalVariance() {
        // Stable incremental algorithm by Welford (TAOCP, vol 2, ed 3, p 232)
        func variance(_ samples: [Double]) -> Double {
            var mean = 0.0
            var s = 0.0
            for k in 0 ..< samples.count {
                let x = samples[k]
                let meanPrev = mean
                mean = mean + (x - meanPrev) / Double(k + 1)
                s = s + (x - mean) * (x - meanPrev)
            }
            return s / Double(samples.count - 1)
        }
        let s = Statistics(measure: "s", windowSize: 3)
        XCTAssertTrue(s.totalVariance.isNaN)
        s.observe(2.0)
        XCTAssertEqual(0.0, s.totalVariance)
        s.observe(4.0)
        XCTAssertEqual(variance([2,4]), s.totalVariance)
        s.observe(6.0)
        XCTAssertEqual(variance([2,4,6]), s.totalVariance)
        s.observe(8.0)
        XCTAssertEqual(variance([2,4,6,8]), s.totalVariance)
        s.observe(10.0)
        XCTAssertEqual(variance([2,4,6,8,10]), s.totalVariance)
    }

    static var allTests = [
        ("testWindowAverages", testWindowAverages),
        ("testTotalStatistics", testTotalAverage),
        ("testTotalVariance", testTotalVariance)
    ]

}

