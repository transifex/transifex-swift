//
//  ICU.swift
//  Transifex
//
//  Created by Dimitrios Bendilas on 17/7/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

/// Errors that may be thrown when calling the `format()` method
/// of the RenderingStrategyFormatter protocol.
enum RenderingStrategyErrors: Error {
    /// Rendering strategy not supported
    case notSupported
}

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
                       params: [String: Any]) throws -> String
}

/// The ICU rendering strategy
class ICUMessageFormat : RenderingStrategyFormatter {
    static func format(stringToRender: String,
                       localeCode: String,
                       params: [String: Any]) throws -> String {
        throw RenderingStrategyErrors.notSupported
    }
}

/// The platform rendering strategy
class PlatformFormat : RenderingStrategyFormatter {
    
    /// Returns the proper plural rule to use based on the given locale and arguments.
    ///
    /// In order to find the correct rule, it takes advantage of Apple's localization framework
    /// that is based on .stringsdict files. It uses a dummy .stringsdict that has all plurals
    /// and returns the name of the plural as the localized value (e.g. one=one, few=few).
    /// This way, this method finds the rule without implementing the complex CLDR
    /// business logic from scratch.
    static func extractPluralizationRule(locale: Locale,
                                         arguments: [CVarArg]) -> PluralizationRule {
        let key = NSLocalizedString("Transifex.StringsDict.TestKey.%d",
                                    bundle: Bundle.module,
                                    comment: "")
        let pluralizationRule = String(format: key,
                                       locale: locale,
                                       arguments: arguments)
        switch pluralizationRule {
        case "zero":
            return .zero
        case "one":
            return .one
        case "two":
            return .two
        case "few":
            return .few
        case "many":
            return .many
        case "other":
            return .other

        default:
            return .unspecified
        }
    }
    
    static func format(stringToRender: String,
                       localeCode: String,
                       params: [String: Any]) throws -> String {
        // Check if the provided parameters contain an argument array
        // and it can be converted to a [CVarArg] array.
        guard let args = params[Swizzler.PARAM_ARGUMENTS_KEY] as? [Any],
              let cArgs = args as? [CVarArg] else {
            return stringToRender
        }
        
        let locale = Locale(identifier: localeCode)

        // Extract all plurals based on the ICU Message Format
        guard let plurals = stringToRender.extractICUPlurals() else {
            return String.init(format: stringToRender, locale: locale,
                               arguments: cArgs)
        }
        
        // Detect which rule to use
        let rule = extractPluralizationRule(locale: locale,
                                            arguments: cArgs)

        var chosenFormat : String?
        
        // Use the proper format based on the extracted rule
        if let formatRule = plurals[rule] {
            chosenFormat = formatRule
        }
        // Otherwise fallback to the "other" rule
        else {
            chosenFormat = plurals[.other]
        }
        
        guard let format = chosenFormat else {
            return String.init(format: stringToRender, locale: locale,
                               arguments: cArgs)
        }
        
        return String.init(format: format, locale: locale,
                           arguments: cArgs)
    }
    
}
