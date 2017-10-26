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

    /** Note: When overriding this, remember to call super.setUp(). */
    override func setUp() {
        Runtime.reset()
    }

    override func tearDown() {
        Runtime.reset()
    }

}