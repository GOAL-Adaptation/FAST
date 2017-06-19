/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *  Extensions to built-in SWIFT types: Dictionary
 *
 *  author: Ferenc A Bartha
 */

//---------------------------------------

/** Extensions for a Generic Array */
extension Array {

    /** Non-mutating append */
    func appended(with element: Element) -> [Element] {
        
        // Create and mutate a copy
        var copy = self
        copy.append(element)

        // Return the appended array
        return copy
    }
}

//---------------------------------------
