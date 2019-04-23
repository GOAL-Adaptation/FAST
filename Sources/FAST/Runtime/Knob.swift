import LoggerAPI

///////////////////
// Runtime State //
///////////////////

protocol IKnob {
    var name: String { get }
    func setter(_ newValue: Any) -> Void
}

/* Wrapper for a value that can be read freely, but can only be changed by the runtime. */
public class Knob<T> : IKnob {
    public typealias Action = (T, T) -> Void

    var preSetter:  Action
    var postSetter: Action

    // TODO check if these are necessary
    func overridePreSetter(newPreSetter: @escaping Action) -> Void {
        self.preSetter = newPreSetter
    }

    func overridePostSetter(newPostSetter: @escaping Action) -> Void {
        self.postSetter = newPostSetter
    }

    public let name:  String
    var value: T

    public init(_ name: String, _ value: T, _ applicationKnob: Bool = true, _ preSetter: @escaping Action = { _,_ in }, _ postSetter: @escaping Action = { _,_ in }) {
        self.name  = name
        self.value = value
        self.preSetter = preSetter
        self.postSetter = postSetter
        if applicationKnob {
            registerApplicationKnob(self)
        }
    }

    public func get() -> T {
        return self.value
    }

    /** 
     * Make knob controllable by the runtime, by making all configurations
     * specificed by the knobs section of the active intent available to
     * the controller.
     */
    public func control() {
        setApplicationKnobModelFilter(forKnob: self.name, to: [])
    }

    /** 
     * Make knob uncontrollable by the runtime, by making only those 
     * configurations specificed by the knobs section of the active 
     * intent available the controller, whose value for this knob are
     * in the passed value array v, which defaults to a singleton array 
     * containing the current value.
     * 
     * Examples: 
     *   - restrict([1,2]) restricts the values for this knob to [1,2].
     *   - restrict() restricts the values for this knob to [self.value].
     */
    public func restrict(_ vs: [T]? = nil) {
        let values = vs == nil ? [self.value] : vs!
        setApplicationKnobModelFilter(forKnob: self.name, to: values)
    }

    /** 
     * Short-hand for restrict([v]).
     * 
     * Examples: 
     *   - restrict(1) restricts the value for this knob to 1.
     *   - restrict() restricts the value for this knob to self.value.
     */
    public func constant(_ v: T? = nil) {
        restrict(v == nil ? nil : [v!])
    }

    internal func set(_ newValue: T, setters: Bool = true) {
        if setters {
            // for the postSetter
            let oldValue = self.value
            self.preSetter(oldValue, newValue)
            self.value = newValue
            self.postSetter(oldValue, newValue)
            Log.debug("Set knob '\(self.name)' of old value '\(oldValue)' to value '\(newValue)' with setters. Value after preSetter and postSetter: '\(self.value)'.")
        } else {
            Log.debug("Setting knob '\(self.name)' of old value '\(self.value)' to value '\(newValue)' without setters.")
            self.value = newValue
        }
    }

    internal func setter(_ newValue: Any) -> Void {
        switch newValue {
        case let castedValue as T:
            self.set(castedValue)
        default:
            FAST.fatalError("Tried to assign \(newValue) to a knob of type \(T.self).")
        }
    }
    
}
