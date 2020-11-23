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
            
            // ... then extract all purals based on the ICU Message Format
            guard let plurals = stringToRender.extractICUPlurals() else {
                return String.init(format: stringToRender, locale: locale,
                                   arguments: cArgs)
            }
            
            // Extract the "one" and "other" rules
            // TODO: Use the proper rule accordingly
            let pOne = plurals["one"]!
            let pOther = plurals["other"]!
            
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
                    
            return String.init(format: format, locale: localeCode,
                               arguments: cArgs)
        }
        else {
            return stringToRender
        }
    }
    
}
