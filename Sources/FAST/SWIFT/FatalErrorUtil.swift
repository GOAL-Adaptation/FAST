import Foundation
import LoggerAPI

public func fatalError(_ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) -> Never {
    let m = message()
    logAndPostErrorToTh(m)
    Swift.fatalError(m, file: file, line: line)
}
