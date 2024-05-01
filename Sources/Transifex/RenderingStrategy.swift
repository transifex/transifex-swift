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
                                         argument: CVarArg) -> PluralizationRule {
        let key = NSLocalizedString("Transifex.StringsDict.TestKey.%d",
                                    bundle: Bundle.module,
                                    comment: "")
        let pluralizationRule = String(format: key,
                                       locale: locale,
                                       arguments: [argument])
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
              var arguments = args as? [CVarArg] else {
            return stringToRender
        }

        let locale = Locale(identifier: localeCode)

        // Extract all plurals based on the ICU Message Format
        let plurals = stringToRender.extractICUPlurals()

        // No plural rules were found in the original string, fallback to the
        // typical string format.
        guard plurals.count > 0 else {
            return String.init(format: stringToRender,
                               locale: locale,
                               arguments: arguments)
        }

        // Find and extract the tokens, if any.
        let tokens = PluralUtils.extractTokens(from: stringToRender)

        // If no tokens were found, then expect a single plural rule.
        // If there are more than 1 plural rules, pick and process the first one.
        if tokens.count == 0 {
            guard let icuPluralResult = plurals.first?.value,
                    let arg = arguments.first,
                    let resultingString = Self.process(icuPluralResult: icuPluralResult,
                                                       locale: locale,
                                                       arg: arg) else {
                return String.init(format: stringToRender, locale: locale,
                                   arguments: arguments)
            }

            return resultingString
        }

        // In this case there are multiple tokens and potentially other format
        // specifiers, like so:
        // "Device contains %1$#@ICU1@ and %2$#@ICU2@ in %3$ld folders"
        //
        // Ref: https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Strings/Articles/formatSpecifiers.html
        var format = stringToRender

        // Enumerate the extracted tokens
        tokens.forEach { processedTokenResult in
            // Cleaned tokens should be: "ICU1", "ICU2", ...
            let cleanedToken = processedTokenResult.2

            // If the ICU plural result cannot be found, skip this token.
            guard let icuPluralResult = plurals[cleanedToken] else {
                return
            }

            // Token prefix should be: "1$", "2$", ...
            let tokenPrefix = processedTokenResult.1

            // Extract the positional specifier from the tokenPrefix
            guard let positionalSpecifier = Int(String(tokenPrefix.dropLast())) else {
                return
            }

            // Subtract 1, as positional specifiers always start from 1.
            let index = positionalSpecifier - 1

            // Expect to find the index in the `arguments` array.
            guard index >= 0,
                  index < arguments.count else {
                return
            }

            // Process the ICU rule with the correct argument, generating the
            // final string for that rule.
            guard let resultingString = Self.process(icuPluralResult: icuPluralResult,
                                                     locale: locale,
                                                     arg: arguments[index]) else {
                return
            }

            // Replace the specifier for that ICU rule transforming it from
            // `%1$#@ICU1@` to `%1$@`, respecting the positional specifier and
            // adding an Objective-C object format specifier, so that the whole
            // token will be replaced by the resultingString in the end.
            format = format.replacingOccurrences(of: "#@\(cleanedToken)",
                                                 with: "")

            // Replace the original argument for that position with the
            // resultingString, so that it will be used instead of the number in
            // the final string.
            arguments[index] = resultingString
        }

        return String.init(format: format,
                           locale: locale,
                           arguments: arguments)
    }

    /// Given an ICUPluralResult, the locale and the argument, construct the final string for that ICU rule.
    ///
    /// - Parameters:
    ///   - icuPluralResult: The ICUPluralResult structure.
    ///   - locale: The current locale.
    ///   - arg: The argument to be passed, in order to locate the proper plural rule.
    /// - Returns: The final string for that ICU rule.
    private static func process(icuPluralResult: ICUPluralResult,
                                locale: Locale,
                                arg: CVarArg) -> String? {
        // Detect which rule to use
        let rule = extractPluralizationRule(locale: locale,
                                            argument: arg)

        var chosenFormat: String?

        // Use the proper format based on the extracted rule
        if let formatRule = icuPluralResult.extractedPlurals[rule] {
            chosenFormat = formatRule
        }
        // Otherwise fallback to the "other" rule
        else {
            chosenFormat = icuPluralResult.extractedPlurals[.other]
        }

        // If the chosen format cannot be found, bail.
        guard let format = chosenFormat else {
            return nil
        }

        return String.init(format: format,
                           locale: locale,
                           arguments: [arg])
    }
    
}
