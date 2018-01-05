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
    required init(name: String, knobs: [TextApiModule], streamInit: (() -> Void)?) {
        self.name = name
        self.reinit = streamInit

        let applicationKnobs = ApplicationKnobs(submodules: knobs)
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

fileprivate var runtime = Runtime.newRuntime()

@discardableResult public func measure(_ name: String, _ value: Double) -> Double {
    return runtime.measure(name, value)
}

public func optimize(
    _ id: String,
    _ knobs: [TextApiModule],
    usingRuntime providedRuntime: Runtime? = nil,
    architecture: String = "XilinxZcu",
    streamInit: (() -> Void)? = nil,
    establishCommuncationChannel: Bool = true,
    until shouldTerminate: @escaping @autoclosure () -> Bool = false,
    across windowSize: UInt32 = 20,
    samplingPolicy: SamplingPolicy = ProgressSamplingPolicy(period: 1),
    _ routine: @escaping (Void) -> Void)
{
    // initialize runtime
    runtime = providedRuntime ?? Runtime.newRuntime()

    // initialize application and add it to runtime
    let app = Runnable(name: id, knobs: knobs, streamInit: streamInit)
    runtime.registerApplication(application: app)

    // configure runtime
    runtime.initializeArchitecture(name: architecture)
    if establishCommuncationChannel {
        runtime.establishCommuncationChannel()
    }

    // run stream init if needed
    app.initializeStream()

    // start the actual optimization
    optimize(app.name, runtime, until: shouldTerminate, across: windowSize, samplingPolicy: samplingPolicy, routine)
}
