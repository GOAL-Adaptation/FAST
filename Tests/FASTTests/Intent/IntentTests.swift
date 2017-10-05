/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Tests of Intent
 *
 *  author: Adam Duracz
 */

//---------------------------------------

import Source
import XCTest
@testable import FAST

//---------------------------------------

class IntentTests: XCTestCase {

    let compiler = Compiler()

    /** Check that the knob space contains all combinations of knob settings. */
    func testKnobSpace() {  

        if let intentSpec = compiler.compileIntentSpec(source: ThMockRestServer.intent) {

            let knobSpace: [KnobSettings] = intentSpec.knobSpace()
            let k1Range = [1,2,3,4,5]
            let k2Range = [1,2,3,4]
            let k3Range = [1.1,2.2,3.3]
            
            XCTAssertEqual( k1Range.count * k2Range.count * k3Range.count
                          , knobSpace.count )

            for k1v in k1Range {
                for k2v in k2Range {
                    for k3v in k3Range {
                        XCTAssertTrue(knobSpace.contains(where: { (ks: KnobSettings) in
                            ks.settings.count == 3 &&
                                ks.settings["k1"] as! Int == k1v &&
                                ks.settings["k2"] as! Int == k2v &&
                                ks.settings["k3"] as! Double == k3v
                        }))
                    }
                }
            }

        }
        else {
            XCTFail("Failed to compile intent.")
        }

    }

    static var allTests = [
        ("testKnobSpace", testKnobSpace)
    ]

}