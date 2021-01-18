//
//  utils.swift
//  Transifex
//
//  Created by Dimitrios Bendilas on 2/8/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation
import CommonCrypto

/// Return a unique key, based on the given source string and optional context.
///
/// A string can be associated with multiple context values, so the context argument can be a serialized
/// comma-separated string or a single string.
///
/// - Parameters:
///   - sourceString: the actual string
///   - context: an optional context that accompanies the string
/// - Returns: a hash that uniquely identifies the string
public func txGenerateKey(sourceString: String, context: String?) -> String {
    var context: String = context ?? ""
    context = context.replacingOccurrences(of: ",", with: ":")
    let finalString = sourceString + ":" + context
    return finalString.md5()
}

extension String {
    /// Calculates the md5 hash of the current string. Used by the `txGenerateKey` function to generate
    /// the final key for a given source string.
    ///
    /// - Returns: The md5 hash of the string
    func md5() -> String {
        let data = Data(utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}

extension String {
    /// Returns the matches of the provided pattern in the current string as a list of substrings.
    ///
    /// - Parameter pattern: The regular expression pattern to be used
    /// - Returns: The list of substrings of the current string that match the pattern
    func capturedGroups(withRegex pattern: String) -> [[String]] {
        var results: [[String]] = []

        var regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            return results
        }
        
        let matches = regex.matches(in: self, options: [], range: NSRange(location:0, length: self.count))
        
        matches.forEach { match in
            var matchResults: [String] = []
            let lastRangeIndex = match.numberOfRanges - 1
            if lastRangeIndex >= 1 {
                
                for i in 1...lastRangeIndex {
                    let capturedGroupIndex = match.range(at: i)
                    let matchedString = (self as NSString).substring(with: capturedGroupIndex)
                    matchResults.append(String(matchedString))
                }
                if matchResults.count > 0 {
                    results.append(matchResults)
                }
            }
        }
        
        return results
    }
    
    /// Removes the first and last characters from a string, if the string has less than 3 characters, it
    /// returns the same string
    ///
    /// - Returns: Returns a new string with the first and last characters of the original string removed
    func removeFirstAndLastCharacters() -> String {
        guard self.count >= 3 else {
            return self
        }
        
        let indexStart = self.index(self.startIndex, offsetBy: 1)
        let indexEnd = self.index(self.endIndex, offsetBy: -1)

        return String(self[indexStart..<indexEnd])
    }
}
