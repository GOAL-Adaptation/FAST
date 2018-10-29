import LoggerAPI

func parseKnobSetting(setting: Any) -> Any {
    // TODO Add support for other knob types, based on type information in intent spec, and error handling
    if let s = setting as? String {
        if let i = Int(s) {
            return i
        }
        else {
            if let d = Double(s) {
                return d
            }
            else {
                FAST.fatalError("Could not parse knob setting \(setting) of type \(type(of: setting)).")
            }
        }
    }
    else {
        if setting is Double || setting is Int {
            return setting
        }
        else {
            FAST.fatalError("Could not parse knob setting \(setting) of type \(type(of: setting)).")
        }
    }
    return setting
}
