import LoggerAPI

/* A collection of knob values that can be applied to control the system. */
class KnobSettings: Hashable, Codable, CustomStringConvertible {
    let kid: Int // The id of the configuration given in the knobtable
    let settings: [String : Any]

    let hashValue: Int
    
    init(kid: Int, _ settings: [String : Any]) {
        self.kid = kid
        self.settings = settings

        var hash = 0
        for knobName in Array(settings.keys).sorted() {
            if let knobValue = settings[knobName] as? Int {
                hash = hash ^ knobValue &* 16777619
            }
            else if let knobValue = settings[knobName] as? Double {
                hash = hash ^ knobValue.hashValue &* 16777619
            }
            else if let knobValue = settings[knobName] as? String {
                hash = hash ^ knobValue.hashValue &* 16777619
            }
            else {
                FAST.fatalError("Can not compute hash for knob value '\(settings[knobName])' of type '\(type(of: settings[knobName]))'.")            
            }
        }
        self.hashValue = hash
    }

    func apply(runtime: Runtime) {
        for (name, value) in settings {
            runtime.setKnob(name, to: value)
        }
        runtime.currentKnobSettings = self
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

    /* CustomStringConvertible protocol */

    public var description: String { return "KnobSettings(kid: \(kid), hashValue: \(hashValue), settings: \(settings))" }

    /* Codable protocol */

    enum CodingKeys: String, CodingKey {
        case kid
        case settings
        case hashValue
    }

    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kid = try values.decode(Int.self, forKey: .kid)
        // TODO Generalize to handle other knob values than Int:s
        settings = try values.decode([String: Int].self, forKey: .settings)
        hashValue = try values.decode(Int.self, forKey: .hashValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kid, forKey: .kid)
        guard let intSettings = settings as? [String : Int] else {
            FAST.fatalError("Serializing non-integer knob values is not implemented.")
        }
        try container.encode(intSettings, forKey: .settings)
        try container.encode(hashValue, forKey: .hashValue)
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
