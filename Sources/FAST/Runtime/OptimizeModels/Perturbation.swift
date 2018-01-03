import LoggerAPI

/** Perturbation */
struct Perturbation {
    let missionIntent          : IntentSpec
    let availableCores         : UInt16
    let availableCoreFrequency : UInt64
    let missionLength          : UInt64
    let sceneObfuscation       : Double

    init?(json: [String: Any]) {
        if let availableCores         = extract(type: UInt16.self, name: "availableCores"        , json: json)
         , let availableCoreFrequency = extract(type: UInt64.self, name: "availableCoreFrequency", json: json)
         , let missionLength          = extract(type: UInt64.self, name: "missionLength"         , json: json)
         , let sceneObfuscation       = extract(type: Double.self, name: "sceneObfuscation"      , json: json) {

            self.availableCores         = availableCores
            self.availableCoreFrequency = availableCoreFrequency
            self.missionLength          = missionLength
            self.sceneObfuscation       = sceneObfuscation

            if let missionIntentString = json["missionIntent"] as? String {
                if let missionIntent = compiler.compileIntentSpec(source: missionIntentString) {
                    self.missionIntent = missionIntent
                }
                else {
                    Log.error("Unable to compile missionIntent from string: \(missionIntentString), which is part of the perturbation JSON: \(json).")
                    return nil
                }
            }
            else {
                if let missionIntentJson = json["missionIntent"] as? [String : Any] {
                    let missionIntentString = RestServer.mkIntentString(from: json)
                    if let missionIntent = compiler.compileIntentSpec(source: missionIntentString) {
                        self.missionIntent = missionIntent
                    }
                    else {
                        Log.error("Unable to compile missionIntent from string: \(missionIntentString), obtained from missionIntent JSON: \(missionIntentJson), which is part of the perturbation JSON: \(json).")
                        return nil
                    }
                }
                else {
                    Log.error("Unable to parse missionIntent from JSON: \(String(describing: json["missionIntent"])), which is part of the perturbation JSON: \(json).")
                    return nil
                }
            }
        }
        else {
            Log.error("Unable to parse Perturbation from JSON: \(json).")
            return nil
        }
    }
}
