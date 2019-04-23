import Foundation
import LoggerAPI

class WarmupController : Controller {
    
    var firstWindowComplete: Bool = false
    let initialKnobSettings: KnobSettings
    let wrappedController: Controller
    
    var model: Model? { get { return wrappedController.model } }
    var window: UInt32 { get { return wrappedController.window } }

    init(first initialKnobSettings: KnobSettings, then wrappedController: Controller) {
        self.initialKnobSettings = initialKnobSettings
        self.wrappedController = wrappedController
    }

    /** 
     * The first time this method is called it will return a constant schedule based on the initialKnobSettings.
     * Subsequent calls will be forwarded to the wrappedController.
     */
    func getSchedule(_ intent: IntentSpec, _ measureValues: [String : Double]) -> Schedule {
        if firstWindowComplete {
            Log.verbose("Returning initial constant schedule with knob settings: \(initialKnobSettings).")
            firstWindowComplete = true
            return Schedule(constant: initialKnobSettings)
        }
        else {
            return wrappedController.getSchedule(intent, measureValues)
        }
    }

}
