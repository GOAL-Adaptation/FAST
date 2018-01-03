enum InteractionMode: String {
    case Default
    case Scripted
}

extension InteractionMode: InitializableFromString {
    init?(from text: String) {
        self.init(rawValue: text)
    }
}

extension InteractionMode: CustomStringConvertible {
    var description: String {
        return self.rawValue
    }
}
