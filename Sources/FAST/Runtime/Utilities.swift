import Foundation
import LoggerAPI

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
            Log.debug("Loaded file '\(name).\(type)'.")
            return contents            
        }
        catch let error {
            Log.warning("Unable to load file '\(name).\(type)'. \(error)")
            return nil
        }
    }
    else {
        Log.warning("Unable to load file '\(name).\(type)'.")
        return nil
    }
} 