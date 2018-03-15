import LoggerAPI

/** Perturbation */
struct Perturbation {
    let missionIntent          : IntentSpec
    let availableCores         : UInt16
    let availableCoreFrequency : UInt64
    let missionLength          : UInt64
    let sceneObfuscation       : Double

    init?(json: [String: Any], intentOnFile: IntentSpec? = nil) {
        if let availableCores         = extract(type: UInt16.self, name: "availableCores"        , json: json)
         , let availableCoreFrequency = extract(type: UInt64.self, name: "availableCoreFrequency", json: json)
         , let missionLength          = extract(type: UInt64.self, name: "missionLength"         , json: json)
         , let sceneObfuscation       = extract(type: Double.self, name: "sceneObfuscation"      , json: json) {

            self.availableCores         = availableCores
            self.availableCoreFrequency = availableCoreFrequency
            self.missionLength          = missionLength
            self.sceneObfuscation       = sceneObfuscation

            if let missionIntentString = json["missionIntent"] as? String {
                if let compiledMissionIntent = compiler.compileIntentSpec(source: missionIntentString) as? Compiler.CompiledIntentSpec {
                    self.missionIntent = handleTestParameters(compiledMissionIntent, intentOnFile, availableCores, availableCoreFrequency)
                }
                else {
                    Log.error("Unable to compile missionIntent from string: \(missionIntentString), which is part of the perturbation JSON: \(json).")
                    return nil
                }
            }
            else {
                if let missionIntentJson = json["missionIntent"] as? [String : Any] {
                    let missionIntentString = RestServer.mkIntentString(from: json)
                    if let compiledMissionIntent = compiler.compileIntentSpec(source: missionIntentString) as? Compiler.CompiledIntentSpec {
                        self.missionIntent = handleTestParameters(compiledMissionIntent, intentOnFile, availableCores, availableCoreFrequency)
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

fileprivate func handleTestParameters(
  _ newIntent: Compiler.CompiledIntentSpec,
  _ localIntent: IntentSpec?,
  _ availableCores: UInt16,
  _ availableCoreFrequency: UInt64
) -> IntentSpec {
  guard let fileIntent = localIntent else { return newIntent }

  var mutableNewKnobs = newIntent.knobs

  for (knobName, knobInfo) in fileIntent.knobs {
    switch knobName {
    case "utilizedCores":
      let values = (knobInfo.0 as! [Int]).filter { $0 <= Int(availableCores) }
      if values.count >= 1 {
        let refValue = values.max()!
        mutableNewKnobs[knobName] = (values, refValue)
      }
    case "utilizedCoreFrequency":
      let values = (knobInfo.0 as! [Int]).filter { $0 <= Int(availableCoreFrequency) }
      if values.count >= 1 {
        let refValue = values.max()!
        mutableNewKnobs[knobName] = (values, refValue)
      }
    default:
      continue
    }
  }

  return Compiler.CompiledIntentSpec(
    name: newIntent.name,
    knobs: mutableNewKnobs,
    measures: newIntent.measures,
    constraint: newIntent.constraint,
    constraintName: newIntent.constraintName,
    costOrValue: newIntent.costOrValue,
    optimizationType: newIntent.optimizationType,
    trainingSet: newIntent.trainingSet,
    objectiveFunctionRawString: newIntent.objectiveFunctionRawString
  )
}
