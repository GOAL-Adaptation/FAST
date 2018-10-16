import LoggerAPI

/* A strategy for switching between KnobSettings, based on the input index. */
public class Schedule {
    let schedule: (_ progress: UInt32) -> KnobSettings
    let oscillating: Bool
    init(_ schedule: @escaping (_ progress: UInt32) -> KnobSettings, oscillating: Bool) {
        self.schedule = schedule
        self.oscillating = oscillating
    }
    init(constant:  KnobSettings) {
        self.schedule = { (_: UInt32) in constant }
        self.oscillating = false
    }
    subscript(index: UInt32) -> KnobSettings {
        get {
            Log.debug("Querying schedule at index \(index)")
            return schedule(index)
        }
    }
}
