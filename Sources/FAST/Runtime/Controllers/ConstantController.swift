class ConstantController : Controller {
    let model: Model? = nil
    let window: UInt32 = 1

    private let knobSettings: KnobSettings

    init(knobSettings: KnobSettings) {
        self.knobSettings = knobSettings
    }

    init() {
        // FIXME Eliminate undefined-value representations (-1 and [:]) below
        //       by making the Runtime.controller optional.
        self.knobSettings = KnobSettings(kid: -1, [:])
    }

    func getSchedule(_ intent: IntentSpec, _ measureValues: [String : Double]) -> Schedule {
        return Schedule({ (_: UInt32) -> KnobSettings in
            return self.knobSettings
        })
    }
}
