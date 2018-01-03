///////////////////
// Runtime State //
///////////////////

/* Wrapper for a value that can be read freely, but can only be changed by the runtime. */
public class Knob<T> {
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

    public init(_ name: String, _ value: T, _ preSetter: @escaping Action = {_,_ in }, _ postSetter: @escaping Action = {_,_ in }) {
        self.name  = name
        self.value = value
        self.preSetter = preSetter
        self.postSetter = postSetter

        Runtime.knobSetters[name] = self.setter
    }

    public func get() -> T {
        return self.value
    }

    internal func set(_ newValue: T, setters: Bool = true) {
        if setters {
            // for the postSetter
            let oldValue = self.value

            self.preSetter(oldValue, newValue)
            self.value = newValue
            self.postSetter(oldValue, newValue)
        } else {
            self.value = newValue
        }
    }

    internal func setter(_ newValue: Any) -> Void {
        switch newValue {
        case let castedValue as T:
            self.set(castedValue)
        default:
            fatalError("Tried to assign \(newValue) to a knob of type \(T.self).")
        }
    }
}
