//
//  ICU.swift
//  TransifexNative
//
//  Created by Dimitrios Bendilas on 17/7/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

/// A protocol for classes that implement different rendering strategies
protocol RenderingStrategyFormatter {
    /// Formats the passed string using a certain locale code and parameters
    /// and returns the final string to be presented in the UI.
    ///
    /// - Parameters:
    ///   - stringToRender: The string to format
    ///   - localeCode: The locale code
    ///   - params: A dictionary of parameters that can be used when formating the string
    static func format(stringToRender: String,
                       localeCode: String,
                       params: [String: Any]) -> String
}

/// The ICU rendering strategy
class ICUMessageFormat : RenderingStrategyFormatter {
    static func format(stringToRender: String,
                       localeCode: String,
                       params: [String: Any]) -> String {
        // TODO: Define Message Format grammar and render the string
        return stringToRender
    }
}

/// The platform rendering strategy
class PlatformFormat : RenderingStrategyFormatter {
    static func format(stringToRender: String,
                       localeCode: String,
                       params: [String: Any]) -> String {
        // If the provided parameters contain an argument array...
        if let args = params[Swizzler.PARAM_ARGUMENTS_KEY] as? [Any],
           // ... which has at least 1 item
           args.count > 0,
           // ... and can be converted to a [CVarArg] array
           let cArgs = args as? [CVarArg] {
            
            // ... then perform a dummy ICU pluralization parsing
            guard let plurals = extractICUPlurals(string: stringToRender) else {
                return String.init(format: stringToRender, locale: Locale.current,
                                   arguments: cArgs)
            }
            
            // Extract the "one" and "other" rules
            let pOne = plurals.0
            let pOther = plurals.1
            
            // Fallback to the "one" rule if the type of the first argument
            // can't be used.
            var format = pOne
            
            // Check the first argument in the array if its type is an integer
            // or a unsigned integer.
            if let firstArgument = args[0] as? Int {
                format = (firstArgument == 1 ? pOne : pOther)
            }
            else if let firstArgument = args[0] as? UInt {
                format = (firstArgument == 1 ? pOne : pOther)
            }
                    
            return String.init(format: format, locale: Locale.current,
                               arguments: cArgs)
        }
        else {
            return stringToRender
        }
    }
    
    typealias PluralOne = String
    typealias PluralOther = String
    typealias Plurals = ( PluralOne, PluralOther)
    
    /// Simple ICU parser for extracting "one" and "other" rules from a pluralized string as fetched from CDS
    /// - Parameter string: The pluralized string
    /// - Returns: A tuple containing the string formats for the "one" and "other" rules
    static func extractICUPlurals(string: String) -> Plurals? {
        let substring = string.removeFirstAndLastCharacters()

        let pattern = #"\{.*?\}"#
        let regex : NSRegularExpression
        
        do {
            regex = try NSRegularExpression(pattern: pattern, options: [])
        }
        catch {
            return nil
        }
        
        var pluralOne : PluralOne? = nil
        var pluralOther : PluralOther? = nil
        
        let range = NSRange(substring.startIndex..<substring.endIndex,
                            in: substring)

        regex.enumerateMatches(in: substring,
                               options: [],
                               range: range) { (match, _, stop) in
            guard let match = match else { return }

            guard let firstCaptureRange = Range(match.range,
                                                in: substring) else {
                return
            }
               
            let string = String(substring[firstCaptureRange]).removeFirstAndLastCharacters()
            
            if pluralOne == nil {
                pluralOne = string
            }
            else if pluralOther == nil {
                pluralOther = string
            }
        }
        
        guard let pOne = pluralOne,
              let pOther = pluralOther else {
            return nil
        }
        
        return (pOne, pOther)
    }
}

extension String {
    
    /// Removes the first and last characters from a string, if the string has less than 3 characters, it
    /// returns the same string
    ///
    /// - Returns: Returns a new string with the first and last characters of the original string removed
    public func removeFirstAndLastCharacters() -> String {
        guard self.count >= 3 else {
            return self
        }
        
        let indexStart = self.index(self.startIndex, offsetBy: 1)
        let indexEnd = self.index(self.endIndex, offsetBy: -1)

        return String(self[indexStart..<indexEnd])
    }
}
