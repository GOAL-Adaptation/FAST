// These knobs simulate changes to the environment during a test
class ScenarioKnobs: TextApiModule {
    let name = "scenarioKnobs"

    var subModules = [String : TextApiModule]()

    // Number of inputs to be processed across a mission
    var missionLength: Knob<UInt64>

    init(_ key: [String]) {
        self.missionLength   = Knob(name: "missionLength",    from: key, or: 1000, preSetter: { assert($1 > 0) })
        self.addSubModule(newModule: missionLength)
    }
}
