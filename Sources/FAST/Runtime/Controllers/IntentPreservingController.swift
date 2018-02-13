import Foundation
import LoggerAPI
import FASTController

class IntentPreservingController : Controller {
    let model: Model? // Always defined for this Controller
    let window: UInt32
    let fastController: FASTController
    let intent: IntentSpec

    init?(_ model: Model,
          _ intent: IntentSpec,
          _ window: UInt32) {
        let sortedModel = model.sorted(by: intent.constraintName)
        self.model = sortedModel
        self.window = window
        self.intent = intent
        if let constraintMeasureIdx = sortedModel.measureNames.index(of: intent.constraintName) {
            self.fastController =
                FASTController( model: sortedModel.getFASTControllerModel()
                              , constraint: intent.constraint
                              , constraintMeasureIdx: constraintMeasureIdx
                              , window: window
                              , optType: intent.optimizationType
                              , ocb: intent.costOrValue
                              , initialModelEntryIdx: sortedModel.initialConfigurationIndex!
                              )
        }
        else {
            Log.error("Intent inconsistent with active model: could not match constraint name '\(intent.constraintName)' stated in intent with a measure name in the active model, whose measures are: \(model.measureNames). ")
            exit(1)
            return nil
        }
    }

    func getSchedule(_ intent: IntentSpec, _ measureValues: [String : Double]) -> Schedule {
        // FIXME Replace global measure store with custom ordered collection that avoids this conversion
        // FIXME This code duplicates code in Intent.swift. Generalize both when doing the above.
        var values = [Double]()
        for measureName in self.model!.measureNames {
            if let v = measureValues[measureName] {
                values.append(v)
            }
            else {
                fatalError("Measure '\(measureName)', present in model, has not been registered in the application.")
            }
        }
        let s = fastController.computeSchedule(tag: 0, measures: values) // FIXME Pass meaningful tag for logging
        return Schedule({ (i: UInt32) -> KnobSettings in
            return self.model![Int(i) < s.nLowerIterations ? s.idLower : s.idUpper].knobSettings
        })
    }
}
