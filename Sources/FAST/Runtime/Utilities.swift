import Foundation
import LoggerAPI
import PerfectHTTP

@discardableResult func synchronized<L: NSLocking, T>(_ lock: L, routine: () -> T) -> T {
    var res: T
    lock.lock()
    res = routine()
    lock.unlock()
    return res
}

func readFile( withName name: String, ofType type: String
             , fromBundle bundle: Bundle = Bundle.main ) -> String? {

    if let path = bundle.path(forResource: name, ofType: type) {
        do {
            let contents = try String(contentsOfFile: path, encoding: String.Encoding.utf8)
              .split(separator: "\n").filter({ !String($0).hasPrefix("#") }).joined(separator: "\n")
            Log.verbose("Loaded file '\(path)'.")
            return contents
        }
        catch let error {
            Log.warning("Unable to load file '\(path)'. \(error)")
            return nil
        }
    }
    else {
        Log.warning("No file '\(name).\(type)' in \(bundle).")
        return nil
    }

}

func withOpenFile( atPath path: String
                 , append: Bool = false
                 , _ body: (OutputStream) -> () ) {
    if let outputStream = OutputStream(toFileAtPath: path, append: append) {
        outputStream.open()
        body(outputStream)
        outputStream.close()
    } else {
        Log.error("Unable to open file '\(path)'")
    }
}

func utcDateString() -> String {
    let utcDateFormatter = DateFormatter()
    utcDateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
    utcDateFormatter.timeZone = TimeZone(identifier: "GMT")
    return utcDateFormatter.string(from: Date())
}

@discardableResult func logAndPostErrorToTh(_ errorMessage: String) -> [String : Any]? {
    Log.error(errorMessage)
    return RestClient.sendRequest(to: "error", withBody: [
        "time"    : utcDateString(),
        "message" : errorMessage
    ])
}
