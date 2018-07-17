import Foundation
import LoggerAPI
import HeliumLogger

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

fileprivate var runtime: Runtime!

/** Register a dynamically created application knob, that is, one instantiated from inside the optimize loop's body. */
func registerApplicationKnob(_ knob: TextApiModule) {
    // Knobs that are instantiated outside the optimize loop are registered in 
    // the Runnable initializer, and will thus be skipped in the follwing if-let
    if 
        let k = knob as? IKnob,
        let r = runtime,
        let application = r.application,
        let applicationAsRunnable = application as? Runnable,
        let applicationKnobs = applicationAsRunnable.subModules["applicationKnobs"]
    {
        r.knobSetters[knob.name] = k.setter
        applicationKnobs.addSubModule(newModule: knob)
    }
}

/** 
 * Set application knob model filter, stored in runtime.modelFilters[], which are applied
 * to contoller models when the controller is initialized.
 * Used to implement toggling of control for knobs, by:
 *  - filtering configurations that match an array of knob values (to "restrict the knob"),
 *  - including configurations for all values of this knob (to "enable control for the knob").
 */
func setApplicationKnobFilter(forKnob knobName: String, to targetKnobValues: [Any]) {
    guard let r = runtime else {
        FAST.fatalError("Attempt to set model filter for knob '\(knobName)' before runtime is initialized.")
    }
    let someTargetKnobValuesIsNotInt = targetKnobValues.map{ $0 is Int }.contains(false)
    if someTargetKnobValuesIsNotInt {
        FAST.fatalError("Currently application knob filters must consist only of Int values. Offending filter: \(targetKnobValues).")
    }
    let filterName = "filter values for knob \(knobName)"
    // If targetKnobValue is empty, clear the filter for this knob
    if targetKnobValues.isEmpty {
        r.modelFilters[filterName] = nil // Model will not be trimmed w.r.t. this knob in Runtime.initializeController()
        Log.debug("Clearing model filter for knob '\(knobName)'.")
    }
    // Otherwise, set a filter that leaves only configurations whose value for this knob is in targetKnobValue
    else {
        Log.debug("Setting model filter for knob '\(knobName)' based on value array '\(targetKnobValues)'.")
        r.modelFilters[filterName] = { (someConfiguration: Configuration) in 
            if let someConfigurationsKnobValue = someConfiguration.knobSettings.settings[knobName] {
                if let cv = someConfigurationsKnobValue as? (Int) {
                    // Check if cv is in targetKnobValues
                    for v in targetKnobValues {
                        if (v as! Int) == cv {
                            return true
                        }
                    }
                    return false
                } 
                else {
                    FAST.fatalError("Knob '\(knobName)' in model has value '\(someConfigurationsKnobValue)' of unsupported type: '\(type(of: someConfigurationsKnobValue))'. Can not set application knob filter.")
                }
            }
            else {
                FAST.fatalError("Knob '\(knobName)' is missing from model. Can not set application knob filter.")
            }
        }
    }
    r.reinitializeController()
}

@discardableResult public func measure(_ name: String, _ value: Double) -> Double {
    return runtime.measure(name, value)
}

public func optimize(
    _ id: String,
    _ knobs: [TextApiModule],
    usingRuntime providedRuntime: Runtime? = nil,
    architecture: String = "XilinxZcu",
    streamInit: (() -> Void)? = nil,
    until shouldTerminate: @escaping @autoclosure () -> Bool = false,
    across windowSize: UInt32 = 20,
    samplingPolicy: SamplingPolicy = ProgressSamplingPolicy(period: 1),
    _ routine: @escaping () -> Void)
{

    struct StandardError: TextOutputStream {
        func write(_ text: String) {
            guard let data = text.data(using: String.Encoding.utf8) else { return }
            FileHandle.standardError.write(data)
        }
    }
    let logLevel = initialize(type: LoggerMessageType.self, name: "logLevel", from: ["proteus","runtime"], or: .verbose)
    HeliumStreamLogger.use(logLevel, outputStream: StandardError())

    // initialize runtime
    runtime = providedRuntime ?? Runtime.newRuntime()

    // initialize application and add it to runtime
    let app = Runnable(name: id, knobs: knobs, streamInit: streamInit)
    runtime.registerApplication(application: app)

    // configure runtime
    runtime.initializeArchitecture(name: architecture)

    // run stream init if needed
    app.initializeStream()

    // start the actual optimization
    optimize(app.name, runtime, until: shouldTerminate, across: windowSize, samplingPolicy: samplingPolicy, routine)
}
