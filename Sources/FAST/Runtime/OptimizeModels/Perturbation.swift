import LoggerAPI

/** Perturbation */
struct Perturbation {
    let missionIntent          : IntentSpec
    let availableCores         : UInt16
    let availableCoreFrequency : UInt64
    let missionLength          : UInt64

    let scenarioChanged        : Bool

    init?(json: [String: Any]) {
        if 
            let availableCores         = extract(type: UInt16.self, name: "availableCores"        , json: json),
            let availableCoreFrequency = extract(type: UInt64.self, name: "availableCoreFrequency", json: json),
            let missionLength          = extract(type: UInt64.self, name: "missionLength"         , json: json)
        {
            self.availableCores         = availableCores
            self.availableCoreFrequency = availableCoreFrequency
            self.missionLength          = missionLength

            if let missionIntentString = json["missionIntent"] as? String {
                if let compiledMissionIntent = compiler.compileIntentSpec(source: missionIntentString) as? Compiler.CompiledIntentSpec {
                    (self.missionIntent, self.scenarioChanged) =
                      handleTestParameters(compiledMissionIntent, availableCores, availableCoreFrequency)
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
                        (self.missionIntent, self.scenarioChanged) =
                          handleTestParameters(compiledMissionIntent, availableCores, availableCoreFrequency)
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

    func asDict() -> [String : Any] {
        return 
            [ "missionIntent"          : missionIntent
            , "availableCores"         : availableCores
            , "availableCoreFrequency" : availableCoreFrequency
            , "missionLength"          : missionLength
            ]
    }

}

fileprivate func handleTestParameters(
  _ newIntent: Compiler.CompiledIntentSpec,
  _ availableCores: UInt16,
  _ availableCoreFrequency: UInt64
) -> (IntentSpec, Bool) {
  var scenarioChanged = false
  var knobs = newIntent.knobs

  for (knobName, knobInfo) in knobs {
    switch knobName {
    case "utilizedCores":
      let values = (knobInfo.0 as! [Int]).filter { $0 <= Int(availableCores) }
      if values.count >= 1 {
        let refValue = values.max()!
        knobs[knobName] = (values, refValue)
        scenarioChanged = true
      }
    case "utilizedCoreFrequency":
      let values = (knobInfo.0 as! [Int]).filter { $0 <= Int(availableCoreFrequency) }
      if values.count >= 1 {
        let refValue = values.max()!
        knobs[knobName] = (values, refValue)
        scenarioChanged = true
      }
    default:
      continue
    }
  }

  return (Compiler.CompiledIntentSpec(
    name: newIntent.name,
    knobs: knobs,
    measures: newIntent.measures,
    constraints: newIntent.constraints,
    costOrValue: newIntent.costOrValue,
    optimizationType: newIntent.optimizationType,
    trainingSet: newIntent.trainingSet,
    objectiveFunctionRawString: newIntent.objectiveFunctionRawString), scenarioChanged)
}
