/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *  Types that are (fallibly) initializable from a String
 *
 *  author: Ferenc A Bartha
 */

//---------------------------------------

/** The protocol for a fallible initializer */
public protocol InitializableFromString {

    init?(from text: String)

}

//---------------------------------------
/** Extensions to built-in SWIFT types */

// TODO add ints, doubles, standard types

/** Extension for String */
extension String: InitializableFromString {

    public init?(from text: String) {
        self = text
    }
}

/** Extension for Int */
extension Int: InitializableFromString {

    public init?(from text: String) {
        if let value = Int(text) {
            self = value
        } else {
            return nil
        }
    }
}

//---------------------------------------
