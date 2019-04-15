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

    func toKnobTableLine(knobNames: [String]) -> String {
        let knobValueStringsInOrder = knobNames.map{ "\(self.knobSettings.settings[$0]!)" }
        return knobValueStringsInOrder.joined(separator: ",")
    }

    func isIn(intent spec: IntentSpec) -> Bool {
        return self.knobSettings.settings.map{ (knobName: String, knobValue: Any) in  
            if let (knobRange,_) = spec.knobs[knobName] {
                if 
                    let v = knobValue as? Int,
                    let r = knobRange as? [Int] 
                {
                    return r.contains(v)
                } 
                else {
                    if 
                        let v = knobValue as? String,
                        let r = knobRange as? [String] 
                    {
                        return r.contains(v)
                    } 
                    else {
                        FAST.fatalError("Knob \(knobName) in model has value '\(knobValue)' of unsupported type: '\(type(of: knobValue))'.")
                    }
                }
            }
            else {
                return true
            }
        }.reduce(true, { $0 && $1 })
    }

}
