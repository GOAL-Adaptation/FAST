import LoggerAPI

enum ApplicationExecutionMode {
    // Run application with adaptation.
    case Adaptive

    // Run application without adaptation.
    case NonAdaptive

    // Run application, without adaptation, once for every configuration in the intent specification.
    case ExhaustiveProfiling

    // Let [appCfg0, appCfg1, .., appCfgn] be the list of application configurations, where appCfg0
    // is the reference configuration specified in the intent specification.
    // Let [sysCfg0, sysCfg1, ..., sysCfgm] be the list of system configurations, where sysCfg0
    // is the reference configuration specified in the intent specification.
    // Run application, without adaptation, once for each configuration in the list
    // [(appCfg0, sysCfg0), (appCfg0, sysCfg1), (appCfg0, sysCfg2), ..., (appCfg0, sysCfgm),
    //  (appCfg1, sysCfg0), (appCfg2, sysCfg0), ..., (appCfgn, sysCfg0)]
    case EmulatorTracing

    // Run application, without adaptation, for a percentage of the configurations in the intent
    // specification. The default is to profile all (100%) of the configurations. When only part
    // of the configurations are profiled, the extremeValues parameter selects whether the extreme
    // values of ordered knob ranges should be included (the remaining percentage is distributed
    // uniformly across ranges).
    case SelectiveProfiling(percentage: Int, extremeValues: Bool)
}

extension ApplicationExecutionMode: Equatable {
    static func == (lhs: ApplicationExecutionMode, rhs: ApplicationExecutionMode) -> Bool {
        switch (lhs, rhs) {
        case (.Adaptive, .Adaptive),
             (.NonAdaptive, .NonAdaptive),
             (.ExhaustiveProfiling, .ExhaustiveProfiling),
             (.EmulatorTracing, .EmulatorTracing):
            return true
        case (let .SelectiveProfiling(pl, el), let .SelectiveProfiling(pr, er)):
            return pl == pr && el == er
        default:
            return false
        }
    }
}

/** Extension for ApplicationExecutionMode */
extension ApplicationExecutionMode: InitializableFromString {
    public init?(from text: String) {
        switch text {
        case "Adaptive":
            self = .Adaptive
        case "NonAdaptive":
            self = .NonAdaptive
        case "ExhaustiveProfiling":
            self = .ExhaustiveProfiling
        case "EmulatorTracing":
            self = .EmulatorTracing
        default:
            Log.warning("Failed to initialize ApplicationExecutionMode from string '\(text)'.")
            return nil
        }
    }
}
