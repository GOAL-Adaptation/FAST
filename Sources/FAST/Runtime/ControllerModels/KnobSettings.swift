import LoggerAPI

/* A collection of knob values that can be applied to control the system. */
class KnobSettings {
    let kid: Int // The id of the configuration given in the knobtable
    let settings: [String : Any]
    init(kid: Int, _ settings: [String : Any]) {
        self.kid = kid
        self.settings = settings
    }
    func apply(runtime: Runtime) {
        for (name, value) in settings {
            runtime.setKnob(name, to: value)
        }
        Log.debug("Applied knob settings.")
    }

    /**
    * Assume knob value is of type Int or Double, return true
    * iff this.settings contains the given otherSettings.
    * Used in filtering knob settings from a given array of KnobSettings.
    */
    func contains(_ otherSettings: [String: Any]) -> Bool {
        for (knobName, knobValue) in otherSettings {
            switch knobValue {
            case is Int:
                if !settings.contains { key, value  in (key == knobName) && (value as? Int == knobValue as? Int)} {
                    return false
                }
            case is Double:
                if !settings.contains { key, value  in (key == knobName) && (value as? Double == knobValue as? Double)} {
                    return false
                }
            default:
                return false
            }
        }
        return true
    }
}

/**
* Used in filtering out duplicate KnobSettings in an array of KnobSettings.
*/
extension KnobSettings: Equatable {
    static func == (lhs: KnobSettings, rhs: KnobSettings) -> Bool {
        return lhs.contains(rhs.settings) && rhs.contains(lhs.settings)
    }
}
