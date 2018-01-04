// These knobs control the interaction mode (e.g. scripted) and application execution mode (e.g. profiling)
class RuntimeKnobs: TextApiModule {
    let name = "RuntimeKnobs"

    var subModules = [String : TextApiModule]()

    var interactionMode: Knob<InteractionMode>

    var applicationExecutionMode: Knob<ApplicationExecutionMode>

    init(_ key: [String], runtime: Runtime) {
        self.interactionMode = Knob(name: "interactionMode", from: key, or: InteractionMode.Default, preSetter: runtime.changeInteractionMode)
        self.applicationExecutionMode = Knob(name: "applicationExecutionMode", from: key, or: ApplicationExecutionMode.Adaptive)
        self.addSubModule(newModule: interactionMode)
        self.addSubModule(newModule: applicationExecutionMode)
    }
}
