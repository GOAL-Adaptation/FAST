/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Intent Specification Compiler
 *
 *  author: Adam Duracz
 *
 */

//---------------------------------------

import Foundation
import LoggerAPI
import AST
import Parser
import Source
import Diagnostic
import FASTController
import struct Expression.AnyExpression

//---------------------------------------

/** 
 * Used to translate an intent specification AST into an IntentSpec object.
 * Expressions are translated into executable SWIFT code by representing each
 * sub-expression as a closure, whose enviroment is obtained from the measures
 * listed in the intent specification.
 */
public class Compiler {

    public init() {}

    struct HeliumLoggerDiagnosticConsumer : DiagnosticConsumer {
        func consume(diagnostics: [Diagnostic]) {
            for d in diagnostics {
                Log.verbose("\(d.location) \(d.level): \(d.kind.diagnosticMessage)")
            }
        }
    }

    /* 
        Work-around to parse until knob constraints can be handled by swift-ast 
        Returns (fileContentWithoutKnobConstraints, knobConstraints), where 
        knobConstraints is nil whenever the fileContent does not contain a knob constraint.
    */
    func separateKnobConstraintsFromRestOfIntentSpec(source fileContent: String) -> (String,String?) {

        let sectionNames = ["knobs", "measures", "intent", "trainingSet"]

        func extractSection(_ sectionName: String) -> String? {
            let stopParsingHereRegex = 
                sectionNames.filter{ $0 != sectionName }
                            .map{ "(?:\($0))" } // sections may end with another section
                            .joined(separator: "|") 
                            + "|(?:$)" // sections may end with end of the file (string)
            let sectionExtractorRegex =
                "(?:\(sectionName)((.|\n)+?)(?=\(stopParsingHereRegex)))"
            return fileContent
                .range(of: sectionExtractorRegex, options: .regularExpression)
                .map{ "\(fileContent[$0])"}
        }

        guard let knobSection = extractSection("knobs") else {
            FAST.fatalError("Could not extract knobs section from intent specification: '\(fileContent)'.")
        }
        guard let measuresSection = extractSection("measures") else {
            FAST.fatalError("Could not extract knobs section from intent specification: '\(fileContent)'.")
        }
        guard let intentSection = extractSection("intent") else {
            FAST.fatalError("Could not extract knobs section from intent specification: '\(fileContent)'.")
        }
        guard let trainingSetSection = extractSection("trainingSet") else {
            FAST.fatalError("Could not extract knobs section from intent specification: '\(fileContent)'.")
        }

        let knobSectionComponents = knobSection.components(separatedBy: "such that")

        switch knobSectionComponents.count {
            case 1:
                return (fileContent, nil)
            case 2:
                let knobSectionWithoutConstraints = knobSectionComponents[0]
                let knobConstraints = knobSectionComponents[1]
                let intentWithoutKnobConstraint = 
                    knobSectionWithoutConstraints + measuresSection + intentSection + trainingSetSection
                return (intentWithoutKnobConstraint, knobConstraints) 
            default:
                FAST.fatalError("Malformed knob section: '\(knobSection)'.")
        }

    }

    /** 
     * Parse an intent specification from a String `source`,
     * then compile its expressions into executable SWIFT code.
     */
    public func compileIntentSpec(source fileContent: String) -> IntentSpec? {
        let diagnosticConsumer = HeliumLoggerDiagnosticConsumer()

        let (fileContentWithoutKnobConstraints, knobConstraints) = 
            separateKnobConstraintsFromRestOfIntentSpec(source: fileContent)

        let parser = IntentParser(source: SourceFile(content: fileContentWithoutKnobConstraints))
        guard let topLevelDecl = try? parser.parse(),
                    let firstStatement = topLevelDecl.statements.first else {
            DiagnosticPool.shared.report(withConsumer: diagnosticConsumer)
            Log.warning("Failed to parse intent: \(fileContentWithoutKnobConstraints).")
            return nil
        }
        
        DiagnosticPool.shared.report(withConsumer: diagnosticConsumer)
                
        if let intentExpr = firstStatement as? IntentExpression {
            let measures = compileMeasures(intentExpr).sorted()  // sorted array of all meassure names
            var measuresStore: [String : Int] = [:]              // key: measure name, value: index of the measure name in the measures array.
            for i in 0 ..< measures.count {
                measuresStore[measures[i]] = i
            }
            return CompiledIntentSpec(
                  name             : intentExpr.intentSection.intentDecl.name
                , knobs            : compileKnobs(intentExpr)
                , measures         : measures
                , constraints      : compileConstraints(intentExpr)
                , optimizationType : intentExpr.intentSection.intentDecl.optimizationType
                , trainingSet      : compileTrainingSet(intentExpr)
                , objectiveFunctionRawString : intentExpr.intentSection.intentDecl.optimizedExpr.textDescription
                , knobConstraintsRawString : knobConstraints
            )

        }
        else {
            Log.warning("Could not parse intent specification: \(firstStatement).")
            return nil
        }
    }

    /** SWIFT representation of a FAST intent specification file. */
    class CompiledIntentSpec : IntentSpec {
            let name             : String                               // name of application
            let knobs            : [String : ([Any], Any)]              // list of knobs, each with range and reference
            let measures         : [String]                             // alphabetically sorted list of measure names
            let constraints      : [String : (Double, ConstraintType)]  // dynamic multi constraints
            let costOrValue      : ([Double]) -> Double // takes an array of measure values corresponding to all the measures 
                                                        // sorted in alphabetical order, and computes the optimized function
                                                        // represented in the objectiveFunctionRawString parameter.
            let optimizationType : FASTControllerOptimizationType
            let trainingSet      : [String]

            var objectiveFunctionRawString : String?    // the textual representation of the objective function.
            var knobConstraintsRawString   : String?    // the textual representation of the knob constraints.

        init( name             : String
                , knobs            : [String : ([Any], Any)]
                , measures         : [String]
                , constraints      : [String : (Double, ConstraintType)]
                , optimizationType : FASTControllerOptimizationType
                , trainingSet      : [String]
                , objectiveFunctionRawString : String? = nil
                , knobConstraintsRawString : String? = nil
            ) 
        {
            self.name             = name            
            self.knobs            = knobs           
            self.measures         = measures        
            self.constraints      = constraints      
            self.optimizationType = optimizationType
            self.trainingSet      = trainingSet         
            self.objectiveFunctionRawString = objectiveFunctionRawString
            self.knobConstraintsRawString = knobConstraintsRawString

            self.costOrValue = { measureValuesArray in
                guard let objectiveFunctionString = objectiveFunctionRawString else {
                    FAST.fatalError("Objective function is not defined.")
                }
                
                // Get the environment dictionary of all the measures, 
                // assuming measureValuesArray[i] is the value of measures[i]:
                var measureValuesDictionary = [String:Double]()
                for i in 0 ..< measures.count {
                    measureValuesDictionary[measures[i]] = measureValuesArray[i]
                }

                // Build an AnyExpression with the objectiveFunctionString and the environement
                // measureValuesDictionary, and let it do the magic evaluating itself.
                let expression = AnyExpression(
                    objectiveFunctionString,
                    constants: measureValuesDictionary
                )
                guard let result = try? expression.evaluate() as Double else {
                    FAST.fatalError("Failed to evaluate objective function: '\(expression)', as a Double, in environment: '\(measureValuesDictionary)'.")
                }
                return result
            }
        }
        public func satisfiesKnobConstraints(knobSettings: KnobSettings) -> Bool {
            guard var constraint = knobConstraintsRawString else {
                return true
            }

            func evalBoolOp(_ op: String, l: Any, r: Any, _ function: (Bool,Bool) -> Bool) -> Bool {
                guard let leftBool = l as? Bool else {
                    FAST.fatalError("Left operand for knob constraint \(l) \(op) \(r) is not boolean.")
                }
                guard let rightBool = r as? Bool else {
                    FAST.fatalError("Right operand for knob constraint \(l) \(op) \(r) is not boolean.")
                }
                return function(leftBool,rightBool)
            }

            func evalFromOp(_ op: String, l: Any, r: Any, _ function: (Any, Any) -> Bool) -> Bool {
                return function(l,r)
            }

            func equalTo(_ l: Any, _ r: Any) -> Bool {
                switch (l,r) {
                    case let (ld,rd) as (Double,Double):
                        return ld == rd
                    case let (li,ri) as (Int,Int):
                        return li == ri
                    case let (ls,rs) as (String,String):
                        return ls == rs
                    case let (lb,rb) as (Bool,Bool):
                        return lb == rb
                    case let (la,ra) as ([Any],[Any]):
                        if la.count != ra.count {
                            return false
                        }
                        for i in 0 ..< la.count {
                            if !equalTo(la[i],ra[i]) {
                                return false
                            }
                        }
                        return true
                    default:
                        FAST.fatalError("Equality check not implemented for: \((type(of:l), type(of:r)))")
                }
            }  

            let expression = AnyExpression(
                constraint,
                options: .boolSymbols, 
                constants: knobSettings.settings.mapValues{
                    switch $0 {
                        case let i as Int    : return NSNumber(value: i)
                        case let d as Double : return NSNumber(value: d)
                        default              : return $0
                    }
                },
                symbols: [
                    .infix("and") : { 
                        args in evalBoolOp("and", l: args[0], r: args[1], { $0 && $1 }) 
                    },
                    .infix("or") : { 
                        args in evalBoolOp("or" , l: args[0], r: args[1], { $0 || $1 }) 
                    },
                    .infix("implies") : { 
                        args in evalBoolOp("implies" , l: args[0], r: args[1], { !$0 || $1 }) 
                    },
                    .infix("from") : { 
                        (args: [Any]) in evalFromOp("from", l: args[0], r: args[1], 
                        { 
                            (l,r) in
                            switch r {
                                case let arr as [Any]:
                                    for e in arr { 
                                        if equalTo(e,l) { return true }
                                    }
                                    return false
                                default:
                                    fatalError("Second parameter of from operator must be an array. It was: '\(r)'.")
                            }
                        }) 
                    }
                ]
            )
            guard let result = try? expression.evaluate() as Bool else {
                FAST.fatalError("Failed to evaluate knob constraints: '\(expression)', as a boolean, in environment: '\(knobSettings.settings)' (from KnobSettings with id \(knobSettings.kid)).")
            }
            return result
        }

    }

    //---------------------------------------

    /** 
     * Translate an Expression AST into a SWIFT literal optional value of type T.
     * Produces nil if the expression does not represent a literal, or if the
     * literal cannot be cast to type T.
     */
    internal func compileTypedLiteral<T>(_ e: Expression) -> T? {
            if let t = compileLiteralOption(e) as? T {
                return t
            }
            else {
                return nil
            } 
    }

    /** Translate an Expression AST into a SWIFT literal optional value. */
    internal func compileLiteralOption(_ e: Expression) -> Any? {
        if let le = e as? LiteralExpression {
            switch le.kind {
                case .integer(let i, _):
                    return i
                case .floatingPoint(let r, _):
                    return r
                default: 
                    return nil
            }
        }
        else {
            return nil
        }
    }

    /** Translate an Expression AST into a SWIFT literal value. */
    internal func compileLiteral(_ e: Expression) -> Any {
        Log.debug("Compiling literal expression '\(e)'.")
        if let le = e as? LiteralExpression {
            switch le.kind {
                case .integer(let i, _):
                    return i
                case .floatingPoint(let r, _):
                    return r
                case .staticString(let s, _):
                    return s
                default: 
                    FAST.fatalError("Unsupported literal: \(le).")
            }
        }
        else {
            FAST.fatalError("Expected literal in compileLiteral. Found: \(e).")
        }
    }

    internal func compileRange(_ range: Expression) -> [Any] {
        switch (range as! LiteralExpression).kind {
            case .array(let elements):
                return elements.map{ compileLiteral($0) }
            default: 
                FAST.fatalError("Could not compile knob range in compileRange: \(range).")
        }
    }

    internal func compileReference(_ reference: Expression) -> Any {
        return compileLiteral(reference)
    }

    /** Extract the map of knob declarations [name: (range, reference)] from a parsed intent specification.  */
    internal func compileKnobs(_ intentExpr: IntentExpression) -> [String : ([Any], Any)] {
        var res: [String : ([Any], Any)] = [:]
        for kd in intentExpr.knobSection.knobDecls {
            res[kd.name] = (compileRange(kd.range), compileReference(kd.reference))
        }
        return res
    }

    /** Extract the list of measure named from a parsed intent specification.  */
    internal func compileMeasures(_ intentExpr: IntentExpression) -> [String] {
        return intentExpr.measureSection.measureDecls.map { (md:MeasureDecl) in md.name }
    }
    
    /** Extract multiple constraints from a parsed intent specification.  */
    internal func compileConstraints(_ intentExpr: IntentExpression) -> [String : (Double, ConstraintType)] {
        return intentExpr.intentSection.intentDecl.constraints.mapValues({ (compileTypedLiteral($0.0)!, $0.1) })
    }

    /** Compile the training set descriptor into an array of commands to pass to the application during training. */
    internal func compileTrainingSet(_ intentExpr: IntentExpression) -> [String] {
        let commandsExpr = intentExpr.trainingSetSection.trainingSetDecl.commands
        if let commands = commandsExpr as? LiteralExpression {
            switch commands.kind {
                case .array(let elements):
                    return elements.map{ 
                        if let s: String = compileTypedLiteral($0) {
                            return s
                        }
                        else {
                            FAST.fatalError("Expected training set element string in compileTrainingSet. Found: \($0).")
                        }
                    }
                default: 
                    FAST.fatalError("Unsupported training set descriptor found in compileTrainingSet: \(commands.kind).")
            }
        }
        else {
            FAST.fatalError("Could not compile training set descriptor found in compileTrainingSet: \(commandsExpr).")
        }
    }

}
