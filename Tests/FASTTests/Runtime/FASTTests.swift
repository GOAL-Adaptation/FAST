/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Tests of Main File
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import XCTest
@testable import FAST

//---------------------------------------

class FASTTests: XCTestCase {

    /** 
     * If FAST is unable to load the intent or model files, an optimize should 
     * behave like a while(true) loop. 
     */
    func testOptimizeWithoutIntentAndModel() {
        
        let threshold = 100
        var optimizeState: Int = 0
        var whileState: Int = 0

        optimize("NO_SUCH_INTENT", []) {
            if optimizeState < threshold {
                optimizeState += 1
            }
            else { Runtime.shouldTerminate = true }
        }

        while(true) {
            if whileState < threshold { 
                whileState += 1
            }
            else { break }
        }

        XCTAssertTrue(optimizeState == whileState)

    }

}

