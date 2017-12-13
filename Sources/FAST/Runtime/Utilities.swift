import Foundation
import LoggerAPI
import PerfectHTTP

func synchronized<L: NSLocking>(_ lock: L, routine: () -> ()) {
    lock.lock()
    routine()
    lock.unlock()
}

func readFile( withName name: String, ofType type: String
             , fromBundle bundle: Bundle = Bundle.main ) -> String? {

    if let path = bundle.path(forResource: name, ofType: type) {       
        do {
            let contents = try String(contentsOfFile: path, encoding: String.Encoding.utf8)
            Log.debug("Loaded file '\(path)'.")
            return contents
        }
        catch let error {
            Log.warning("Unable to load file '\(path)'. \(error)")
            return nil
        }
    }
    else {        
        Log.warning("No file '\(name).\(type)' in \(Bundle.main).")
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