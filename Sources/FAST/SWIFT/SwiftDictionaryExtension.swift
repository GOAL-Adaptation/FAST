/*
 *  FAST: An implicit programing language based on SWIFT
 *
 *  Extensions to built-in SWIFT types: Dictionary
 *
 *  author: Ferenc A Bartha
 */

//---------------------------------------

/** Extensions for Dictionary */
extension Dictionary {

    //-----------------
    /** Merging two Dictionaries */

    /** Non-mutating merge with another Dictionary of the same kind into a new Dictionary */
    func merged(with dictionary: Dictionary<Key,Value>) -> Dictionary<Key,Value> {
        
        // Non-mutating method
        var result = self
        
        // Add each key value pair into the result
        dictionary.forEach { key, value in result.updateValue(value, forKey: key) }
        
        return result
    }

    /** Mutating merge with another Dictionary of the same kind */
    mutating func merge(with dictionary: Dictionary<Key,Value>) -> () {
        
        // Add each key value pair into the current Dictionary
        dictionary.forEach { key, value in self.updateValue(value, forKey: key) }
        
    }

}

//---------------------------------------
