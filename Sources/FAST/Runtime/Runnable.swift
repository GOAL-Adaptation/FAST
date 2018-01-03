class Runnable: Application, EmulateableApplication, StreamApplication {
    class ApplicationKnobs: TextApiModule {
        let name = "applicationKnobs"
        var subModules = [String : TextApiModule]()

        init(submodules: [TextApiModule]) {
            for module in submodules {
              self.addSubModule(newModule: module)
            }
        }
    }

    let name: String
    var subModules = [String : TextApiModule]()
    let reinit: (() -> Void)?

    /** Initialize the application */
    required init(name: String, knobs: [TextApiModule], architecture: String = "XilinxZcu", streamInit: (() -> Void)? = nil) {
        self.name = name
        self.reinit = streamInit

        initRuntime()

        for knob in knobs {
            guard let knob = knob as? IKnob else { fatalError("Only knobs are allowed to be passed in.") }
            knob.addToRuntime()
        }
        let applicationKnobs = ApplicationKnobs(submodules: knobs)

        Runtime.registerApplication(application: self)
        Runtime.initializeArchitecture(name: architecture)
        Runtime.establishCommuncationChannel()

        self.addSubModule(newModule: applicationKnobs)
    }

    /** Look up the id (in the database) of the current application configuration. */
    func getCurrentConfigurationId(database: Database) -> Int {
        return database.getCurrentConfigurationId(application: self)
    }

    func initializeStream() {
        reinit?()
    }
}

public func optimize(
    _ id: String,
    _ knobs: [TextApiModule],
    until shouldTerminate: @escaping @autoclosure () -> Bool = false,
    across windowSize: UInt32 = 20,
    samplingPolicy: SamplingPolicy = ProgressSamplingPolicy(period: 1),
    _ routine: @escaping (Void) -> Void )
{
    let app = Runnable(name: id, knobs: knobs)
    optimize(app.name, until: shouldTerminate, across: windowSize, samplingPolicy: samplingPolicy, routine)
}

protocol IKnob {
    var name: String { get }
    func setter(_ newValue: Any) -> Void
    func addToRuntime()
}
extension Knob : IKnob {
    func addToRuntime() {
        Runtime.knobSetters[name] = setter
    }
}
