/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        Intent Specification Parser
 *
 *  authors: Dung X Nguyen, Adam Duracz
 *
 */

//---------------------------------------

import Foundation
import AST
import Parser
import Source
import FASTController

//---------------------------------------

/**
 * A knob declaration consists of a name, a range of values, and a reference value
 */
public class KnobDecl : Expression {
    public var name: String
    public var range: Expression
    public var reference: Expression

    public init(name: String, range: Expression, reference: Expression) {
        self.name = name
        self.range = range
        self.reference = reference
    }

    public var textDescription: String {
        return "KnobDecl(\(name), \(range), \(reference))"
    }

    public var lexicalParent: ASTNode? = nil
    public var sourceRange: SourceRange = .INVALID
}

/** A knob section consists of a comma separated list of knob declarations. */
public class KnobSection : Expression {
    public var knobDecls: [KnobDecl]

    public init(knobDecls: [KnobDecl]) {
        self.knobDecls = knobDecls
    }

    public var textDescription: String {
        return "KnobSection(\(knobDecls))"
    }

    public var lexicalParent: ASTNode? = nil
    public var sourceRange: SourceRange = .INVALID
}

/**
 *  A measure declaration consists of a measure name and its type
 */
public class MeasureDecl : Expression {
    public var name: String
    public var type: String

    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }

    public var textDescription: String {
        return "MeasureDecl(\(name), \(type))"
    }

    public var lexicalParent: ASTNode? = nil
    public var sourceRange: SourceRange = .INVALID
}

/**
 * A measure section consists of a comma separated list of measure declarations.
 */
public class MeasureSection : Expression {
    public var measureDecls: [MeasureDecl]

    public init(measureDecls: [MeasureDecl]){
        self.measureDecls = measureDecls
    }

    public var textDescription: String {
        return "MeasureSection(\(measureDecls))"
    }

    public var lexicalParent: ASTNode? = nil
    public var sourceRange: SourceRange = .INVALID  
}

/**
 * An intent declaration consists of a name, 
 * an optimization type (maximize or minimize), an expression to be optimized,
 * a constraint name, and a constraint expression.
 */
public class IntentDecl : Expression {
    public var name: String
    public var optimizationType : FASTControllerOptimizationType
    public var optimizedExpr: Expression
    public var constraintName: String
    public var constraint:Expression

    public init(name: String, optimizationType : FASTControllerOptimizationType,
        optimizedExpr: Expression, constraintName: String, constraint:Expression) {
        self.name = name
        self.optimizationType = optimizationType
        self.optimizedExpr = optimizedExpr
        self.constraintName = constraintName
        self.constraint = constraint
    }

    public var textDescription: String {
        return "IntentDecl(\(name), \(optimizationType), \(optimizedExpr), \(constraintName), \(constraint))"
    }

    public var lexicalParent: ASTNode? = nil
    public var sourceRange: SourceRange = .INVALID    
}

/**
 * An intent section consists of an intent declaration.
 */
public class IntentSection : Expression {
    public var intentDecl: IntentDecl

    public init(intentDecl: IntentDecl) {
        self.intentDecl = intentDecl
    }

    public var textDescription: String {
        return "IntentSection(\(intentDecl))"
    }

    public var lexicalParent: ASTNode? = nil
    public var sourceRange: SourceRange = .INVALID
}

/**
 *  A training set declaration consists of a collection of command line strings.
 */
public class TrainingSetDecl : Expression {
    var commands: Expression

    public init(commands: Expression) {
        self.commands = commands
    }

    public var textDescription: String {
        return "TrainingSetDecl(\(commands))"
    }

    public var lexicalParent: ASTNode? = nil
    public var sourceRange: SourceRange = .INVALID
}

/**
 * A training set section consists of a training set declaration.
 */
public class TrainingSetSection : Expression {
    public var trainingSetDecl: TrainingSetDecl

    public init(trainingSetDecl: TrainingSetDecl) {
        self.trainingSetDecl = trainingSetDecl
    }

    public var textDescription: String {
        return "TrainingSetSection(\(trainingSetDecl))"
    }

    public var lexicalParent: ASTNode? = nil
    public var sourceRange: SourceRange = .INVALID
}

/**
 * An intent expression has a knob section, a measure sectio, an intent section,
 * and a training set section.
 */
public class IntentExpression : Expression {
    public var knobSection: KnobSection
    public var measureSection: MeasureSection
    public var intentSection: IntentSection
    public var trainingSetSection: TrainingSetSection

    public init(knobSection: KnobSection, measureSection: MeasureSection, 
                        intentSection:IntentSection, trainingSetSection: TrainingSetSection) {
        self.knobSection = knobSection
        self.measureSection = measureSection
        self.intentSection = intentSection
        self.trainingSetSection = trainingSetSection
    }

    public var textDescription: String {
        return "IntentExpression(\n  \(knobSection),\n  \(measureSection),\n  \(intentSection),\n  \(trainingSetSection))"
    }
    
    public var lexicalParent: ASTNode? = nil
    public var sourceRange: SourceRange = .INVALID
}

/**
 * Parser for intent specification source files.
 */
class IntentParser : Parser {

    /* Knob Section */

    func parseKnobDecl(config: ParserExpressionConfig = ParserExpressionConfig())
    throws -> KnobDecl {
        if case .identifier(let knobName, _) = _lexer.look().kind {
            _lexer.advance(by:1)
            if case.assignmentOperator = _lexer.look().kind {
                _lexer.advance(by:1)
                let knobValue = try super.parseExpression(config: config)
                if case .identifier(let myKeyword, _) = _lexer.look().kind, myKeyword == "reference" {
                    _lexer.advance(by:1)
                    let referenceExpr = try super.parseExpression(config: config)
                return KnobDecl(name: knobName, range: knobValue, reference: referenceExpr)
                } else {
                fatalError("Expected 'reference'. Found: \(_lexer.look().kind).")
                }
            } else {
                fatalError("Expected '=' after knob name. Found: \(_lexer.look().kind).")
            }
        } else {
            fatalError("Expected a knob name. Found: \(_lexer.look().kind).")
        }
    }

    func parseKnobSection(config: ParserExpressionConfig = ParserExpressionConfig())
    throws -> KnobSection {
                _lexer.advance(by: 1)
            var knobDecls = [KnobDecl]() 
            repeat {
                let knobDecl = try parseKnobDecl(config: config)
                knobDecls.append(knobDecl)
                if case .identifier(let myKeyword, _) = _lexer.look().kind, myKeyword == "measures" {
                    break
                }
            } while true 
            return KnobSection(knobDecls: knobDecls)  
    }

    /* Measure Section */

    func parseMeasureDecl(config: ParserExpressionConfig = ParserExpressionConfig())
    -> MeasureDecl {
        if case .identifier(let measureName, _) = _lexer.look().kind,
            _lexer.look(ahead: 1).kind == .colon {
            _lexer.advance(by:2)
            if case .identifier(let measureType, _) = _lexer.look().kind {
                _lexer.advance(by:1)
                return MeasureDecl(name: measureName, type: measureType)
            } else {
                fatalError("Expected a measure type. Found: \(_lexer.look().kind).")
            }
        } else {
            fatalError("Expected a measure name followed by a colon. Found: \(_lexer.look().kind).")
        }
    }

    func parseMeasureSection(config: ParserExpressionConfig = ParserExpressionConfig())
    -> MeasureSection {
            _lexer.advance(by: 1)
            var measureDecls = [MeasureDecl]() 
            repeat {
                    let measureDecl = parseMeasureDecl(config: config)
                    measureDecls.append(measureDecl)
                    if case .identifier(let myKeyword, _) = _lexer.look().kind, myKeyword == "intent" {
                        break
                    }
            } while true
            return MeasureSection(measureDecls: measureDecls)   
    }

    /* Intent Section */

    func parseIntentDecl(config: ParserExpressionConfig = ParserExpressionConfig())
    throws -> IntentDecl {
        if case .identifier(let intentName, _) = _lexer.look().kind {
            _lexer.advance(by: 1)
            if case .identifier(let optimizer, _) = _lexer.look().kind,
            (optimizer == "max" || optimizer == "min" ), _lexer.look(ahead: 1).kind == .leftParen {
                _lexer.advance(by: 2)
                let optimizationType = (optimizer == "max") ? FASTControllerOptimizationType.maximize : FASTControllerOptimizationType.minimize
                let optimizedExpr = try super.parseExpression(config: config)
                if _lexer.look().kind == .rightParen,
              case .identifier(let suchKeyword, _) = _lexer.look(ahead: 1).kind, suchKeyword == "such",
              case .identifier(let thatKeyword, _) = _lexer.look(ahead: 2).kind, thatKeyword == "that",
              case .identifier(let constraintName, _) = _lexer.look(ahead: 3).kind,
                    _lexer.look(ahead: 4).kind == .binaryOperator("==") {
                        _lexer.advance(by: 5)
                        let constraint = try super.parseExpression(config: config)
                        return IntentDecl(name: intentName, optimizationType : optimizationType,
                                        optimizedExpr: optimizedExpr, constraintName: constraintName, constraint: constraint)
                } else {
                    fatalError("expected right parenthesis followed by 'such that', a measure name, and '=='. Found: \(_lexer.look().kind).")
                }
            } else {
                fatalError("expected 'max' or 'min' followed by a left parenthesis. Found: \(_lexer.look().kind).")
            }
        } else {
            fatalError("expected an intent name. Found: \(_lexer.look().kind).")
        }
    }

    func parseIntentSection(config: ParserExpressionConfig = ParserExpressionConfig()) 
    throws -> IntentSection {
        _lexer.advance(by: 1)
        return IntentSection(intentDecl: try parseIntentDecl(config:config))
    }

    /* Training Set Section */

    func parseTrainingSetDecl(config: ParserExpressionConfig = ParserExpressionConfig()) 
    throws -> TrainingSetDecl {
        return TrainingSetDecl(commands: try super.parseExpression(config: config))
    }

    func parseTrainingSetSection(config: ParserExpressionConfig = ParserExpressionConfig()) 
    throws -> TrainingSetSection {
        _lexer.advance(by: 1)
        return TrainingSetSection(trainingSetDecl: try parseTrainingSetDecl(config:config))
    }

    /* Intent Specification */

    override func parseExpression(config: ParserExpressionConfig = ParserExpressionConfig())
    throws -> Expression {
        if case .identifier(let myKeyword, _) = _lexer.look().kind, myKeyword == "knobs" {
            let knobSection = try parseKnobSection(config: config)
            let measureSection = parseMeasureSection(config: config)
            let intentSection = try parseIntentSection(config:config)
            if case .identifier(let myKeyword, _) = _lexer.look().kind, myKeyword == "trainingSet" {
                let trainingSetSection = try parseTrainingSetSection(config:config)
                return IntentExpression(knobSection: knobSection, measureSection: measureSection,
                                        intentSection:intentSection, trainingSetSection: trainingSetSection)
            } else {
                fatalError("expected 'trainingSet'. Found: \(_lexer.look().kind).")
            }
        } else {
            return try super.parseExpression(config: config)
        }
    }

}
