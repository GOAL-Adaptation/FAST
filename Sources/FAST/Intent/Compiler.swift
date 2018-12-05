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

    /** 
     * Parse an intent specification from a String `source`,
     * then compile its expressions into executable SWIFT code.
     */
    public func compileIntentSpec(source fileContent: String) -> IntentSpec? {
        let diagnosticConsumer = HeliumLoggerDiagnosticConsumer()
        let parser = IntentParser(source: SourceFile(content: fileContent))
        guard let topLevelDecl = try? parser.parse(),
                    let firstStatement = topLevelDecl.statements.first else {
            DiagnosticPool.shared.report(withConsumer: diagnosticConsumer)
            Log.warning("Failed to parse intent: \(fileContent).")
            return nil
        }
        
        DiagnosticPool.shared.report(withConsumer: diagnosticConsumer)
                
        if let intentExpr = firstStatement as? IntentExpression {
            let measures = compileMeasures(intentExpr).sorted()
            var measuresStore: [String : Int] = [:]
            for i in 0 ..< measures.count {
                measuresStore[measures[i]] = i
            }
            return CompiledIntentSpec(
                    name             : intentExpr.intentSection.intentDecl.name
                , knobs            : compileKnobs(intentExpr)
                , measures         : measures
                , constraints      : compileConstraints(intentExpr)
                , costOrValue      : compileCostOrValue(intentExpr, measuresStore)
                , optimizationType : intentExpr.intentSection.intentDecl.optimizationType
                , trainingSet      : compileTrainingSet(intentExpr)
                , objectiveFunctionRawString : intentExpr.intentSection.intentDecl.optimizedExpr.textDescription
            )

        }
        else {
            Log.warning("Could not parse intent specification: \(firstStatement).")
            return nil
        }
    }

    /** SWIFT representation of a FAST intent specification file. */
    class CompiledIntentSpec : IntentSpec {
            let name             : String
            let knobs            : [String : ([Any], Any)]
            let measures         : [String]
            let constraints      : [String : Double]
            let costOrValue      : ([Double]) -> Double
            let optimizationType : FASTControllerOptimizationType
            let trainingSet      : [String]

            var objectiveFunctionRawString : String?

        init( name             : String
                , knobs            : [String : ([Any], Any)]
                , measures         : [String]
                , constraints      : [String : Double]
                , costOrValue      : @escaping ([Double]) -> Double
                , optimizationType : FASTControllerOptimizationType
                , trainingSet      : [String]
                , objectiveFunctionRawString : String? = nil
            )
        {
            self.name             = name            
            self.knobs            = knobs           
            self.measures         = measures        
            self.constraints      = constraints      
            self.costOrValue      = costOrValue     
            self.optimizationType = optimizationType
            self.trainingSet      = trainingSet         
            self.objectiveFunctionRawString = objectiveFunctionRawString
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

    /** 
     * Translate an Expression AST into a SWIFT expression (in the form of a closure)
     * whose environment is an array of doubles. The store maps a variable (measure)
     * name to an index into this array.
     */
    internal func compileExpression(_ e: Expression, _ store: [String : Int]) -> ([Double]) -> Double {
        if let pe = e as? ParenthesizedExpression {
            Log.debug("Compiling parenthesized expression: \(e)" )
            return compileExpression(pe.expression, store)
        }
        else {
            if let d: Double = compileTypedLiteral(e) {
                return { (_: [Double]) in d }
            }
            else {
                if let identifierExpr = e as? IdentifierExpression,
                     case let .identifier(identifier, _) = identifierExpr.kind {
                    Log.debug("Compiling identifier '\(identifier)'.")
                    if let i = store[identifier.textDescription] {
                        return { (measures: [Double]) in 
                            if i < measures.count {
                                return measures[i]
                            }
                            else {
                                FAST.fatalError("Value for measure \(identifier), present in the store \(store), is missing from the environment \(measures).")        
                            }
                        }
                    }
                    else {
                        FAST.fatalError("Unknown measure: \(identifier).")
                    }
                }
                else {
                    if let eAsBinOpExpr = e as? BinaryOperatorExpression {
                            return compileBinaryOperatorExpression(eAsBinOpExpr, store)
                    } else if let eAsPrefixOpExpr = e as? PrefixOperatorExpression {
                            return compilePrefixOperatorExpression(eAsPrefixOpExpr, store)
                    } else {
                        FAST.fatalError("Unsupported expression found in compileExpression: \(e) of type \(type(of: e)).")
                    }
                }
            }
        }
    }
    
    //---------------------------------------

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
    internal func compileConstraints(_ intentExpr: IntentExpression) -> [String : Double] {
        return intentExpr.intentSection.intentDecl.constraints.mapValues({ compileTypedLiteral($0)! })
    }

    /** Translate a binary operator expression into a SWIFT expression. */
    internal func compileBinaryOperatorExpression(_ e: BinaryOperatorExpression, _ store: [String : Int]) -> ([Double]) -> Double {
        Log.debug("Compiling binary operator expression '\(e)'.")
        let l = compileExpression(e.leftExpression, store)
        let r = compileExpression(e.rightExpression, store)
        switch e.binaryOperator {
            case "+": return { (measures: [Double]) in l(measures) + r(measures) }
            case "-": return { (measures: [Double]) in l(measures) - r(measures) }
            case "*": return { (measures: [Double]) in l(measures) * r(measures) }
            case "/": return { (measures: [Double]) in l(measures) / r(measures) }
            default:
                FAST.fatalError("Unknown operator found in compileBinaryOperatorExpression: \(e.binaryOperator).")
        }
    }

    internal func compilePrefixOperatorExpression(_ e: PrefixOperatorExpression, _ store: [String : Int]) -> ([Double]) -> Double {
        Log.debug("Compiling binary operator expression '\(e)'.")
        let compiled = compileExpression(e.postfixExpression, store)
        switch e.prefixOperator {
            case "-": return { (measures: [Double]) in 0 - compiled(measures) }
            default:
                FAST.fatalError("Unknown operator found in compilePrefixOperatorExpression: \(e.prefixOperator).")
        }
    }

    /** Compile the objective ("cost" or "value") function of the intent into a Swift closure. */
    internal func compileCostOrValue(_ intentExpr: IntentExpression, _ store: [String : Int]) -> ([Double]) -> Double {
        let costOrValueExpr = intentExpr.intentSection.intentDecl.optimizedExpr
        return compileExpression(costOrValueExpr, store)
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
