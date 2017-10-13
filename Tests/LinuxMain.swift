import XCTest
@testable import FASTTests

XCTMain([
    testCase(CompilerTests.allTests),
    testCase(FASTTests.allTests),
    testCase(IntentTests.allTests),
    testCase(OptimizeTests.allTests),
    testCase(RestServerTests.allTests)
])
