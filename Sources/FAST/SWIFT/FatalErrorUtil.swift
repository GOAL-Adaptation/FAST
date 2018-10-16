import Foundation
import LoggerAPI

public func fatalError(_ message: @autoclosure () -> String = "", file: StaticString = #file, line: UInt = #line) -> Never {
    Log.error(message)
    Swift.fatalError(message, file: file, line: line)
}
