import Foundation
import LoggerAPI
import FASTController

class IntentPreservingController : Controller {
    
    let model              : Model? // Always defined for this Controller
    let window             : UInt32
    let fastController     : FASTController
    let intent             : IntentSpec

    init?( _ model: Model
         , _ intent: IntentSpec
         , _ runtime: Runtime
         , _ window: UInt32
         ) 
    {
        assert(intent.constraints.count == 1, "FAST Controller only work in uniconstraint case.")

        let modelSortedByConstraintMeasure = model.sorted(by: intent.constraints.keys.first!)

        self.model              = modelSortedByConstraintMeasure
        self.window             = window
        self.intent             = intent

        if 
            let constraintMeasureIdx = modelSortedByConstraintMeasure.measureNames.index(of: intent.constraints.keys.first!),
            let objectiveFunctionRawString = intent.objectiveFunctionRawString
        {    
            let constraint = (intent.constraints.values.first!).0
            let optType = intent.optimizationType

            Log.debug("Initializing FASTController with constraint: '\(constraint)', constraintMeasureIdx: '\(constraintMeasureIdx)', window: '\(window)', objectiveFunctionRawString: '\(objectiveFunctionRawString)'.")
            self.fastController =
                FASTController( model: modelSortedByConstraintMeasure.getFASTControllerModel()
                              , constraint: constraint
                              , constraintMeasureIdx: constraintMeasureIdx
                              , window: window
                              , optType: optType
                              , ocb: intent.costOrValue
                              , initialModelEntryIdx: 0 // Always 0, since model passed above is sorted by the constraint measure 
                              )

            // Enable logging to standard output
            self.fastController.logFile = FileHandle.standardOutput

        }
        else {
            FAST.fatalError("Intent inconsistent with active model: could not match constraint name '\(intent.constraints.keys.first!)' stated in intent with a measure name in the active model, whose measures are: \(model.measureNames). ")
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
                FAST.fatalError("Measure '\(measureName)', present in model, has not been registered in the application.")
            }
        }
        let s = fastController.computeSchedule(tag: 0, measures: values) // FIXME Pass meaningful tag for logging
        return Schedule(
            { (i: UInt32) -> KnobSettings in
                return self.model![Int(i) < s.nLowerIterations ? s.idLower : s.idUpper].knobSettings
            }, 
            oscillating: s.oscillating
        )
    }
}
