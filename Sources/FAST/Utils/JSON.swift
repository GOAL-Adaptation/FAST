/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *        JSON Conversions
 *
 *  authors: Ferenc A Bartha, Adam Duracz
 *
 *  SWIFT implementation is based on the C library [pemu] implemented by
 *  Ferenc A Bartha, Dung X Nguyen, Jason Miller, Adam Duracz
 *
 *  Core functionalities implemented in this file are based on 
 *  the example provided by IBM for BlueSocket
 */

//-------------------------------

import Foundation

//-------------------------------

// TODO status is Dictionary [String : Any], the new custom types eventhough extend String are not recognized as Strings by the 
// JSONSerializer (See Utils/JSON.swift), hence a JSON object cannot be created automatically. Find a way to hack it or use another library or custom implementation

/** SWIFT built-in conversion to JSON */    
func convertToJson(from rawData: Any) -> Data? {

    // Recursion on rawData, every leaf has to be recognized as of valid type
    if JSONSerialization.isValidJSONObject(rawData) {
        do {

            return try JSONSerialization.data(withJSONObject: rawData, options: .prettyPrinted)

        } catch {

            return nil
        }
    } else {

        return nil
    }
}

/** 
 *  Custom Json conversion, as a temporary workaround to:
 *    https://bugs.swift.org/browse/SR-4783
 *
 *  NOTE: Does not attempt to handle encoding of strings.
 */    
func convertToJsonSR4783(from rawData: Any) -> String {

    if let dict = rawData as? [String : Any] {
        return "{" + dict.map { (s,a) in "\"\(s)\": " + convertToJsonSR4783(from: a) }.joined(separator: ", ") + "}"
    }
    else {
        if let arr = rawData as? [Any] {
            return "[" + arr.map{ a in convertToJsonSR4783(from: a) }.joined(separator: ", ") + "]"
        }
        else {
            if let s = rawData as? String {
                return "\"\(s)\""
            }
            else {
                return "\(rawData)"
            }
        }
    }

}

//-------------------------------
