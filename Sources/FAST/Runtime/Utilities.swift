import Foundation

func synchronized<L: NSLocking>(_ lock: L, routine: () -> ()) {
    lock.lock()
    routine()
    lock.unlock()
}

extension Dictionary {
    init(elements:[(Key, Value)]) {
        self.init()
        for (key, value) in elements {
            updateValue(value, forKey: key)
        }
    }
}
