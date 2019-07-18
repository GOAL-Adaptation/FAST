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

            // Find the index in the sorted model of the configuration that will be active when getSchedule() is first called.
            guard let currentKnobSettings = runtime.currentKnobSettings else {
                FAST.fatalError("Can not initialize IntentPreservingController (at iteration \(runtime.getMeasure("iteration"))) without knowledge of current knob settings.")
            }
            guard let initialModelEntryIdx = modelSortedByConstraintMeasure.configurations.index(where: { $0.knobSettings == currentKnobSettings }) else {
                FAST.fatalError("Current configuration (at iteration \(runtime.getMeasure("iteration")!)) with the following knob settings missing from model: \(currentKnobSettings). Model: \(model).")
            }

            Log.debug("Initializing FASTController with constraint: '\(constraint)', constraintMeasureIdx: '\(constraintMeasureIdx)', window: '\(window)', objectiveFunctionRawString: '\(objectiveFunctionRawString)'.")
            var fastControllerOptType: FASTControllerOptimizationType
            switch optType {
                case .minimize: fastControllerOptType = FASTControllerOptimizationType.minimize
                case .maximize: fastControllerOptType = FASTControllerOptimizationType.maximize
            }
            self.fastController =
                FASTController( model: modelSortedByConstraintMeasure.getFASTControllerModel()
                              , constraint: constraint
                              , constraintMeasureIdx: constraintMeasureIdx
                              , window: window
                              , optType: fastControllerOptType
                              , ocb: intent.costOrValue
                              , initialModelEntryIdx: initialModelEntryIdx
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
