struct TestParameter {
  let _availableCores: Int32?
  let _availableCoreFrequency: Int64?
  let _missionLength: Int64?
  let _sceneObfuscation: Double?

  init(from json: [String: Any]) {
    // FIXME Set scenario knobs listed in the Perturbation JSON Schema:
    //       availableCores, availableCoreFrequency, missionLength, sceneObfuscation.
    //       This requires:
    //       1) extending the Runtime with a handler for scenario knob setting,
    //       2) adding missionLength and sceneObfuscation knobs, perhaps to a new
    //          "Environment" TextApiModule.

    _availableCores = json["availableCores"] as? Int32
    _availableCoreFrequency = json["availableCoreFrequency"] as? Int64
    _missionLength = json["missionLength"] as? Int64
    _sceneObfuscation = json["sceneObfuscation"] as? Double
  }

  var hasAvailableCores: Bool { return _availableCores != nil }
  var hasAvailableCoreFrequency: Bool { return _availableCoreFrequency != nil }
  var hasMissionLength: Bool { return _missionLength != nil }
  var hasSceneObfuscation: Bool { return _sceneObfuscation != nil }

  var availableCores: Int32 { return _availableCores! }
  var availableCoreFrequency: Int64 { return _availableCoreFrequency! }
  var missionLength: Int64 { return _missionLength! }
  var sceneObfuscation: Double { return _sceneObfuscation! }
}
