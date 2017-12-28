// The runtime API this where the channel connects
public class RuntimeApiModule: TextApiModule {
    public let name = "Runtime"
    public var subModules = [String : TextApiModule]()

    public func internalTextApi(
        caller: String,
        message: [String],
        progressIndicator: Int,
        verbosityLevel: VerbosityLevel
    ) -> String {
        func consRet(_ verboseText: String, _ defaultText: String = "") -> String {
            guard case .Verbose = verbosityLevel else { return defaultText }
            return verboseText
        }

        // the internal runtime API handles the process command
        if message[progressIndicator] == "process" {
            if Runtime.runtimeKnobs.interactionMode.get() == .Scripted {
                var stepAmount: UInt64 = 0
                if message[progressIndicator + 1] == "random" {
                    if message.count > progressIndicator + 3 {
                        if  let loBound = Int32(message[progressIndicator + 2]),
                            let hiBound = Int32(message[progressIndicator + 3]) {
                                stepAmount = UInt64(randi(min: loBound, max: hiBound))
                        }
                    }
                } else if let stepNumber = UInt64(message[progressIndicator + 1]) {
                    stepAmount = stepNumber
                }

                if stepAmount > 0 {
                    Runtime.process(numberOfInputs: stepAmount)
                    return consRet("Processed \(stepAmount) input(s).")
                } else {
                    return consRet("Invalid step amount for process: ``" + message.joined(separator: " ") + "`` received from: \(caller).")
                }
            } else {
                return consRet("Invalid process message: ``" + message.joined(separator: " ") + "`` received from: \(caller) as interactionMode is \(Runtime.runtimeKnobs.interactionMode.get()).")
            }
        // the runtime keeps track of the iteration measure
        } else if message[progressIndicator] == "iteration" && message[progressIndicator + 1] == "get" {
            return consRet(
                "Current iteration is: " + String(describing: Runtime.getMeasure("iteration")) + ".",
                String(describing: Runtime.getMeasure("iteration"))
            )
        // invalid message
        } else {
            return consRet("Invalid message: ``" + message.joined(separator: " ") + "'' received from: \(caller).")
        }
    }

    /** get status as a dictionary */
    public func getInternalStatus() -> [String : Any]? {
        return ["iteration" : UInt64(Runtime.getMeasure("iteration")!)] // TODO make sure iteration is always defined, some global init would be nice
    }

    init() {
        self.addSubModule(newModule: Runtime.runtimeKnobs)
    }
}
