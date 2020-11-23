//
//  ICU.swift
//  
//
//  Created by Dimitrios Bendilas on 23/11/20.
//

import Foundation

extension String {

    /// Extracts plural rules from strings that follow the ICU Message Format,
    /// e.g. "one", "few", "other" etc
    ///
    /// The strings need to be structured like this:
    /// "{cnt, plural, one {There is %d table} other {There are %d tables}}"
    /// "{???, plural, one {There is %d table} other {There are %d tables}}"
    /// (the latter is how pluralized strings arrive from CDS).
    ///
    /// Strings that use "{var}" placeholders, like the following, are not supported:
    /// {cnt, plural, one {There is {cnt}} table} other {There are {cnt}} tables}}
    ///
    /// - Parameter string: The pluralized string
    /// - Returns: A dictionary that holds all plural strings found in the given string,
    ///            or nil if the string does not follow the ICU Message Format
    ///            and the pluralized format in particular
    func extractICUPlurals() -> [String: String]? {
        guard self.contains(", plural, ") else {
            return nil
        }
        
        let pattern = #"(zero|one|two|few|many|other)\s*(\{[^}]*\})"#
        let results = self.capturedGroups(withRegex: pattern)
        var plurals: [String: String] = [:]
        
        results.forEach { matchedPair in
            plurals[matchedPair[0]] = matchedPair[1].removeFirstAndLastCharacters()
        }
        return plurals
    }
}

