/* A combination of a collection of knob values and corresponding measure values. */
struct Configuration {
    public let id: Int // FIXME: Eliminate this by making Configuration Equatable
    public let knobSettings: KnobSettings
    public let measureValues: [Double]
    public let measureNames: [String]

    init(_ id: Int, _ knobSettings: KnobSettings, _ measures: [String : Double]) {
        self.id = id
        self.knobSettings = knobSettings
        measureNames = measures.keys.sorted()
        measureValues = measureNames.map{ measures[$0]! }
    }

    private init(_ id: Int, _ knobSettings: KnobSettings, _ measureValues: [Double], _ measureNames: [String]) {
        self.id = id
        self.knobSettings = knobSettings
        self.measureValues = measureValues
        self.measureNames = measureNames
    }

    // FIXME: Eliminate this by making Configuration Equatable
    func with(newId: Int) -> Configuration {
        return Configuration(newId, knobSettings, measureValues, measureNames)
    }
}
