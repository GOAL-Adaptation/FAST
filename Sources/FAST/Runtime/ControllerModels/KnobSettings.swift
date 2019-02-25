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
        Log.debug("Applied knob settings.")
    }

    /**
    * Assume knob value is of type Int, Double, or String, return true
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
            case is String:
                if !settings.contains { key, value  in (key == knobName) && (value as? String == knobValue as? String)} {
                    return false
                }
            default:
                let knobValueType = type(of: knobValue)
                FAST.fatalError("Cannot compare knob values of type \(knobValueType)!")
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

    enum SupportedKnobType: String, Codable {
        case string, int, double
    }

    class Wrapper : Codable {
        let v : Any
        let t : SupportedKnobType
        enum CodingKeys: String, CodingKey {
           case v, t
        }
        init(_ v: Any) {
            self.v = v
            switch v {
                case is Int:
                    t = .int
                case is Double:
                    t = .double
                case is String:
                    t = .string
                default:
                    FAST.fatalError("Knob values can only be Int, Double, or String.")
            }
        }
        required init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            t = try container.decode(SupportedKnobType.self, forKey: .t)
            switch t {
                case .int:
                    v = try container.decode(Int.self, forKey: .v)
                case .double:
                    v = try container.decode(Double.self, forKey: .v)
                case .string:
                    v = try container.decode(String.self, forKey: .v)
                default:
                    FAST.fatalError("Decoding only supported for knob values of type Int, Double, or String.")
            }
        }
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(t as SupportedKnobType, forKey: .t)
            switch v {
                case let tv as Int:
                    try container.encode(tv, forKey: .v)
                case let tv as Double:
                    try container.encode(tv, forKey: .v)
                case let tv as String:
                    try container.encode(tv, forKey: .v)
                default:
                    FAST.fatalError("Encoding only supported for knob values of type Int, Double, or String.")
            }
        }
    }

    // Property settings = [String: Any] needs to be encoded as [String: Wrapper], since Any is not encodable
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kid, forKey: .kid)
        let wrappedSettings = Dictionary(settings.map{ ($0.key, Wrapper($0.value)) })
        try container.encode(wrappedSettings, forKey: .settings)
        try container.encode(hashValue, forKey: .hashValue)
    }

    // Since property settings is encoded as [String: Wrapper], it needs to be unwrapped.
    required init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kid = try values.decode(Int.self, forKey: .kid)
        let wrappedSettings = try values.decode([String: Wrapper].self, forKey: .settings)
        self.settings = Dictionary(wrappedSettings.map{ ($0.key, $0.value.v) })
        hashValue = try values.decode(Int.self, forKey: .hashValue)
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
