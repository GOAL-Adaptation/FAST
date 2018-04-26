// These knobs simulate changes to the environment during a test
class ScenarioKnobs: TextApiModule {
    let name = "scenarioKnobs"

    var subModules = [String : TextApiModule]()

    // Number of inputs to be processed across a mission
    var missionLength: Knob<UInt64>
    // Parameter (with range [0.0,1.0]) used to introduce noise in the input
    var sceneImportance: Knob<Double>

    init(_ key: [String]) {
        self.missionLength   = Knob(name: "missionLength",    from: key, or: 1000, preSetter: { assert((0...1000).contains($1)) })
        self.sceneImportance = Knob(name: "sceneImportance", from: key, or: 0.0,  preSetter: { assert((0.0...1.0).contains($1)) })
        self.addSubModule(newModule: missionLength)
        self.addSubModule(newModule: sceneImportance)
    }
}
