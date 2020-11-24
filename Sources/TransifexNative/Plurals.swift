//
//  Plurals.swift
//  TransifexNative
//
//  Created by Dimitrios Bendilas on 23/11/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

enum PluralizationRule : String {
    case unspecified = "unspecified"
    case zero = "zero"
    case one = "one"
    case two = "two"
    case few = "few"
    case many = "many"
    case other = "other"
}

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
    func extractICUPlurals() -> [PluralizationRule: String]? {
        guard self.contains(", plural, ") else {
            return nil
        }
        
        let pattern = #"(zero|one|two|few|many|other)\s*(\{[^}]*\})"#
        let results = self.capturedGroups(withRegex: pattern)
        var plurals: [PluralizationRule: String] = [:]
        
        results.forEach { matchedPair in
            // Convert strings like "few" to the respective enum
            let rule = PluralizationRule(rawValue: matchedPair[0])!
            // Remove the braces from the matched string,
            // e.g. "{%d tables}" -> "%d tables"
            plurals[rule] = matchedPair[1].removeFirstAndLastCharacters()
        }
        return plurals
    }
}

