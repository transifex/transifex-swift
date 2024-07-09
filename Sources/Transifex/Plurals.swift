//
//  Plurals.swift
//  Transifex
//
//  Created by Dimitrios Bendilas on 23/11/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum PluralizationRule : String {
    case unspecified = "unspecified"
    case zero = "zero"
    case one = "one"
    case two = "two"
    case few = "few"
    case many = "many"
    case other = "other"
}

struct ICUPluralResult: Equatable {
    var extractedPlurals: [PluralizationRule: String]
}

extension String {
    private static let ICU_RULE_PATTERN = #"\{([^\s]*?), plural, [^*]*?\}\}"#

    private static let PLURALIZATION_RULE_PATTERN = #"(zero|one|two|few|many|other)\s*(\{[^}]*\})"#

    /// Extracts plural rules from strings that follow the ICU Message Format.
    ///
    /// The strings must contain ICU rules that need to be structured like this:
    /// ```
    /// {cnt, plural, one {There is %d table} other {There are %d tables}}
    /// ```
    /// or
    /// ```
    /// {???, plural, one {There is %d table} other {There are %d tables}}
    /// ```
    /// (the latter is how pluralized strings arrive from CDS).
    ///
    /// The method can extract multiple ICU rules from the given string.
    ///
    /// For example, the following string:
    ///
    /// ```
    /// There %1$#@{term1, plural, one {is %d person} other {are %d people}}@ sitting in %2$#@{term2, plural, one {%d table} two {a couple of tables} other {%d tables}}@ in this restaurant.
    /// ```
    ///
    /// Produces the following result:
    /// ```
    /// [
    ///     "{term1, plural, one {is %d person} other {are %d people}}" : ICUPluralResult(
    ///         extractedPlurals: [
    ///             .one: "is %d person",
    ///             .other: "are %d people"
    ///         ]
    ///     ),
    ///     "{term2, plural, one {%d table} two {a couple of tables} other {%d tables}}": ICUPluralResult(
    ///         extractedPlurals: [
    ///             .one: "%d table",
    ///             .two: "a couple of tables",
    ///             .other: "%d tables"
    ///         ]
    ///     )
    /// ]
    /// ```
    ///
    /// - Parameter string: The pluralized string
    /// - Returns: A dictionary that has a size equal to the number of ICU rules found in the current
    /// string. Each element contains the extracted ICU rule as a key and an ICUPluralResult structure with
    /// the extracted rules as a value.
    func extractICUPlurals() -> [String: ICUPluralResult] {
        // Bail fast if the string does not contain a plural rule.
        guard contains(", plural, ") else {
            return [:]
        }

        // Extract the ICU rules from the strings
        var regex: NSRegularExpression

        do {
            regex = try NSRegularExpression(pattern: Self.ICU_RULE_PATTERN,
                                            options: [])
        }
        catch {
            return [:]
        }

        var matchingICURules: [String:ICUPluralResult] = [:]

        regex
            .matches(in: self,
                      options: [],
                      range: NSRange(location: 0,
                                     length: count))
            .forEach {
                guard $0.numberOfRanges == 2 else {
                    return
                }
                let icuRuleRange = $0.range(at: 0)
                guard !NSEqualRanges(icuRuleRange, NSMakeRange(NSNotFound, 0)) else {
                    return
                }
                let icuRule = (self as NSString).substring(with: icuRuleRange)
                let results = icuRule.capturedGroups(withRegex: Self.PLURALIZATION_RULE_PATTERN)
                var plurals: [PluralizationRule: String] = [:]

                results.forEach { matchedPair in
                    // Convert strings like "few" to the respective enum
                    guard let rule = PluralizationRule(rawValue: matchedPair[0]) else {
                        return
                    }
                    // Remove the curly braces from the matched string
                    // e.g. "{%d tables}" -> "%d tables"
                    plurals[rule] = matchedPair[1].removeFirstAndLastCharacters()
                }

                matchingICURules.updateValue(ICUPluralResult(extractedPlurals: plurals),
                                             forKey: icuRule)
            }

        return matchingICURules
    }
}

/// Class responsible for parsing the collection of CDS XML elements, filtering the proper rules for the device
/// and generating (if needed) the final ICU string to be used by the SDK.
final class XMLPluralParser: NSObject {
    private static let CDS_XML_ID_ATTRIBUTE_DEVICE_TOKEN = "device"
    private static let CDS_XML_ID_ATTRIBUTE_SUBSTITUTIONS_TOKEN = "substitutions"

    private static let ICU_RULE_MISSING_TOKEN = "???"
    private static let ICU_RULE_PLURAL_TOKEN = "plural"

    private static let CDS_XML_ID_ATTRIBUTE_PLURAL_TOKEN = "plural"
    private static let CDS_XML_ID_ATTRIBUTE_DELIMITER = "."

    private static let FIRST_POSITIONAL_SPECIFIER = "%1$"
    private static let VARIABLE_PREFIX: Character = "%"
    private static let POSITIONAL_SPECIFIER_SUFFIX = "$"

    // Constants that should match the device variation strings of the
    // .xcstrings file.
    private static let DEVICE_NAME_IPHONE = "iphone"
    private static let DEVICE_NAME_IPAD = "ipad"
    private static let DEVICE_NAME_IPOD = "ipod"
    private static let DEVICE_NAME_MAC = "mac"
    private static let DEVICE_NAME_WATCH = "applewatch"
    private static let DEVICE_NAME_VISION = "applevision"
    private static let DEVICE_NAME_APPLETV = "appletv"
    private static let DEVICE_NAME_OTHER = "other"

    private var parser: XMLParser
    private var parsedResults: [String: String] = [:]
    private var pendingCDSUnitID: String?
    private var pendingString: String = ""

    required internal init?(pluralString: String) {
        self.parser = XMLParser(data: Data(pluralString.utf8))
        super.init()
        self.parser.delegate = self
    }

    /// Parses the provided plural string XML and generates the final rule.
    ///
    /// - Parameter deviceName: The device name.
    /// - Returns: The final rule to be used.
    private func extract(_ deviceName: String) -> String? {
        if !parser.parse() {
            return nil
        }

        return processParsedResults(deviceName)
    }

    /// - Parameter deviceName: The device name, nil for the general device rule `device.`
    /// - Returns: The synthesized device rule
    private static func deviceRule(with deviceName: String? = nil) -> String {
        return "\(CDS_XML_ID_ATTRIBUTE_DEVICE_TOKEN)\(CDS_XML_ID_ATTRIBUTE_DELIMITER)\(deviceName ?? "")"
    }

    /// - Parameter results: The parsed XML results
    /// - Returns: True if the provided results contain at least one device rule, false otherwise.
    private static func containsDeviceRules(_ results: [String: String]) -> Bool {
        return containsRules(withPrefix: deviceRule(),
                             results: results)
    }

    /// - Parameters:
    ///   - deviceName: The device name
    ///   - results: The parsed XML results
    /// - Returns: True if the provided results contain at least one device rule for the provided device
    /// name, false otherwise.
    private static func containsDeviceRules(for deviceName: String,
                                            results: [String: String]) -> Bool {
        return containsRules(withPrefix: deviceRule(with: deviceName),
                             results: results)
    }

    /// - Parameters:
    ///   - prefix: The prefix to search for
    ///   - results: The parsed XML results
    /// - Returns: Looks up the parsed XML results and returns true if the prefix is found at least once,
    /// false otherwise.
    private static func containsRules(withPrefix prefix: String,
                                      results: [String: String]) -> Bool {
        for (key, _) in results {
            if key.hasPrefix(prefix) {
                return true
            }
        }
        return false
    }

    /// Given the extracted results of the XML parser, generate the final rule to be used or return nil if there
    /// was an error.
    ///
    /// - Parameter deviceName: The device name.
    /// - Returns: The final rule to be used.
    private func processParsedResults(_ deviceName: String) -> String? {
        guard parsedResults.count > 0 else {
            return nil
        }

        var finalResults = parsedResults
        var deviceNameRuleFound = false
        var finalDeviceName = deviceName
        var finalDeviceKey = Self.deviceRule(with: deviceName)

        // If device rules exist in the parsed results, then perform some
        // extra processing.
        if Self.containsDeviceRules(parsedResults) {
            // If the parsed device results include rules for the provided
            // deviceName, everything is OK.
            if Self.containsDeviceRules(for: deviceName,
                                        results: parsedResults) {
                deviceNameRuleFound = true
            }
            // If the provided deviceName cannot be detected in the parsed
            // device results, find a fallback.
            else {
                // For the iPad deviceName, if not found in the rules, fallback:
                // * Firstly to the `iphone` device rules, if found
                // * Otherwise to the `other` device rules, if found.
                if deviceName == Self.DEVICE_NAME_IPAD,
                   Self.containsDeviceRules(for: Self.DEVICE_NAME_IPHONE,
                                            results: parsedResults) {
                    deviceNameRuleFound = true
                    finalDeviceName = Self.DEVICE_NAME_IPHONE
                    finalDeviceKey = Self.deviceRule(with: Self.DEVICE_NAME_IPHONE)
                }

                // For any other deviceName, fallback to `other` device rules.
                if !deviceNameRuleFound,
                   Self.containsDeviceRules(for: Self.DEVICE_NAME_OTHER,
                                            results: parsedResults) {
                    deviceNameRuleFound = true
                    finalDeviceName = Self.DEVICE_NAME_OTHER
                    finalDeviceKey = Self.deviceRule(with: Self.DEVICE_NAME_OTHER)
                }
            }

            // Filter the parsed results and keep:
            // * The device rules for the found device (provided or fallback).
            // * The substitution rules.
            finalResults = parsedResults.filter {
                // If a device name rule has been found, keep those rules
                (deviceNameRuleFound && $0.key.hasPrefix(finalDeviceKey))
                // Do not filter out substitutions as they do not begin with the
                // `device*` schema, but they are still needed.
                || $0.key.hasPrefix(Self.CDS_XML_ID_ATTRIBUTE_SUBSTITUTIONS_TOKEN)
            }
        }

        // If there are no items after filtering, then bail.
        guard finalResults.count > 0 else {
            return nil
        }

        // If only one item is left after filtering (typical for device
        // variation rules), then just return that immediately.
        if finalResults.count == 1 {
            return finalResults.first?.value
        }

        // The rest of the cases must be two:
        // * Substitutions (having a main phrase that contains two or more
        //   tokens).
        // * Device specific plural rules.

        // Case 1: Substitutions.
        // The main phrase that contains the substitutions will be found in:
        // * The element having a "substitutions" key if there are no device
        //   variations, or
        // * The element having the "device.finalDeviceName" key if there are
        //   also device variations.
        // It should be one or the other, if both elements can be found,
        // then something is wrong.
        if finalResults[Self.CDS_XML_ID_ATTRIBUTE_SUBSTITUTIONS_TOKEN] != nil
            || (deviceNameRuleFound && finalResults[finalDeviceKey] != nil) {
            var mainPhrase = finalResults[Self.CDS_XML_ID_ATTRIBUTE_SUBSTITUTIONS_TOKEN]

            if mainPhrase == nil, deviceNameRuleFound {
                mainPhrase = finalResults[finalDeviceKey]
            }

            guard var mainPhrase = mainPhrase else {
                return nil
            }

            // Process the main phrase, adding positional specifiers if needed,
            // so that they can later be used to locate the position of the rule
            // in the argument list.
            //
            // The main phrase is expected to be either:
            // * XCStrings: "This iPhone contains %1$#@token1@ with %2$#@token2@"
            // * Strings Dict: "This iPhone contains %#@token1@ with %#@token2@"
            // The processPhrase() method normalizes that so that even Strings
            // Dict phrases will have positional specifiers (1$, 2$ etc)
            mainPhrase = Self.processPhrase(mainPhrase)

            // Extract tokens from the main phrase.
            PluralUtils.extractTokens(from: mainPhrase).forEach { processedTokenResult in
                // Tokens should be: "%1$#@token1@", "%2$#@token2@", ...
                let token = processedTokenResult.0
                // Token prefix should be: "1$", "2$", ...
                let tokenPrefix = processedTokenResult.1
                // Cleaned tokens should be: "token1", "token2", ...
                let cleanedToken = processedTokenResult.2
                let pluralRules = Self.parsePluralRules(finalResults,
                                                        firstExpectedComponent: Self.CDS_XML_ID_ATTRIBUTE_SUBSTITUTIONS_TOKEN,
                                                        secondExpectedComponent: cleanedToken,
                                                        cleanValueCharacters: tokenPrefix)

                // Generate ICU rule from the plural rules
                if let icuRule = Self.generateICURule(with: cleanedToken,
                                                      pluralRules: pluralRules) {
                    // Leave the token prefix and suffix intact, as they will be
                    // needed when the final string will be rendered in the UI.
                    let tokenReadyICURule = PluralUtils.buildToken(with: tokenPrefix,
                                                                   token: icuRule)
                    mainPhrase = mainPhrase.replacingOccurrences(of: token,
                                                                 with: tokenReadyICURule)
                }
            }

            // Return the final synthesized main phrase that now contains ICU
            // rules.
            return mainPhrase
        }
        // Case 2: Device specific plural rules
        else if deviceNameRuleFound {
            // In this case, the plural rules are expected to have the
            // following format:
            // "device.finalDeviceName.plural.pluralRule"
            let pluralRules = Self.parsePluralRules(finalResults,
                                                    firstExpectedComponent: Self.CDS_XML_ID_ATTRIBUTE_DEVICE_TOKEN,
                                                    secondExpectedComponent: finalDeviceName)

            // Generate ICU rule from the plural rules
            return Self.generateICURule(with: nil,
                                        pluralRules: pluralRules)
        }

        // Something unexpected happened that the logic could not handle.
        //
        // This can happen if neither the provided nor a fallback device name
        // could be found, but there are still substitution rules for other
        // device names. As it is not possible to figure out which rule to use,
        // return nil.
        return nil
    }

    /// Add positional specifiers to a variable / token phrase that does not contain them.
    ///
    /// - Parameter phrase: The original phrase.
    /// - Returns: The phrase with added positional specifiers.
    private class func processPhrase(_ phrase: String) -> String {
        // If the phrase already contains positional specifiers, bail.
        guard !phrase.contains(FIRST_POSITIONAL_SPECIFIER) else {
            return phrase
        }

        var result = phrase

        // Positional specifiers always start from index 1
        var positionalSpecifier = 1
        var currentIndex = result.startIndex

        // Look for the `%` characters that signify variables and tokens.
        while let range = result.range(of: String(VARIABLE_PREFIX),
                                       range: currentIndex..<result.endIndex) {
            let nextIndex = result.distance(from: result.startIndex,
                                            to: range.lowerBound) + 1
            // If the string ends with a `%`, then just bail.
            if nextIndex == result.count {
                break
            }

            // Peek into the next character
            let nextChar = result[result.index(result.startIndex,
                                               offsetBy: nextIndex)]

            // If the character right after `%` is another `%` or a ` ` (space),
            // then do not add a positional specifier and advance by two
            // characters (the current `%` + the next character that was just
            // checked).
            if nextChar == VARIABLE_PREFIX || nextChar == " " {
                currentIndex = result.index(range.lowerBound,
                                            offsetBy: 2)
                continue
            }

            // Replace the `%` with the `%\(positionalSpecifier)$` and advance
            // by the extra characters that have been added.
            let replacement = "\(VARIABLE_PREFIX)\(positionalSpecifier)\(POSITIONAL_SPECIFIER_SUFFIX)"
            result.replaceSubrange(range,
                                   with: replacement)
            positionalSpecifier += 1

            currentIndex = result.index(range.lowerBound,
                                        offsetBy: replacement.count - 1)
        }

        return result
    }

    /// Generates the ICU with an optional token, given the pluralization rules.
    ///
    /// If the pluralization rules array is empty, the method returns nil.
    ///
    /// - Parameters:
    ///   - token: The optional token to be used. If one is not provided then "???" is used.
    ///   - pluralRules: The array of tuples that contain the pluralization rule as the first element
    ///   (e.g. "one", "two", "other" etc) and the string to be used as the second element. The array is
    ///   sorted in respect to the pluralization rules.
    /// - Returns: The generated ICU rule string, nil if there provided array was empty.
    private class func generateICURule(with token: String?,
                                       pluralRules: [(PluralizationRule,String)]) -> String? {
        guard pluralRules.count > 0 else {
            return nil
        }

        var icuRules: [String] = []

        for (pluralRule, value) in pluralRules {
            icuRules.append("\(pluralRule) {\(value)}")
        }

        return "{\(token ?? Self.ICU_RULE_MISSING_TOKEN), \(Self.ICU_RULE_PLURAL_TOKEN), \(icuRules.joined(separator: " "))}"
    }

    /// Validate and parse plural rules.
    ///
    /// - Parameter parsedResults: The parsed results
    /// - Parameter firstExpectedComponent: The first expected component of the key.
    /// - Parameter secondExpectedComponent: The second expected component of the key.
    /// - Returns: An array containing tuples with the plural rule as the first element and the string as
    /// the second one. The array is sorted in respect to the order each key must appear on the final ICU
    /// rule.
    private class func parsePluralRules(_ parsedResults: [String:String],
                                        firstExpectedComponent: String,
                                        secondExpectedComponent: String,
                                        cleanValueCharacters: String? = nil) -> [(PluralizationRule,String)] {
        var pluralRules: [PluralizationRule:String] = [:]

        parsedResults.forEach { (key, value) in
            let components = key.components(separatedBy: Self.CDS_XML_ID_ATTRIBUTE_DELIMITER)
            // Sanity check
            guard components.count == 4,
                  components[0] == firstExpectedComponent,
                  components[1] == secondExpectedComponent,
                  components[2] == Self.CDS_XML_ID_ATTRIBUTE_PLURAL_TOKEN else {
                return
            }

            guard let pluralRule = PluralizationRule(rawValue: components[3]) else {
                return
            }

            if let cleanValueCharacters = cleanValueCharacters,
               cleanValueCharacters.count > 0 {
                pluralRules[pluralRule] = value.replacingOccurrences(of: cleanValueCharacters,
                                                                     with: "")
            }
            else {
                pluralRules[pluralRule] = value
            }
        }

        // Sort rules as they appear in the PluralizationRule enum
        return pluralRules.sorted { $0.key.rawValue < $1.key.rawValue }
    }

    /// There is currently no native way of knowing whether the current iOS application runs on a Vision
    /// device (something like `isiOSAppOnMac` but for Vision devices). So here's a (hacky) way of doing
    /// that until Apple adds a helper method, by using a public class that is only available on VisionOS.
    ///
    /// - Returns: True if the iOS app runs on a Vision device, False otherwise.
    private static func isiOSAppOnVision() -> Bool {
        struct Static {
            static var isOnVisionDevice: Bool = {
                return NSClassFromString("UIWindowSceneGeometryPreferencesVision") != nil
            }()
        }
        return Static.isOnVisionDevice
    }

    /// Returns the current device name in the form used by the `.xcstrings` file type.
    ///
    /// - Returns: The current device name
    private class func currentDeviceName() -> String {
#if os(iOS)
        // For iOS applications running on a Mac or a Vision device (as
        // 'Designed for iPhone' / 'Designed for iPad'), we need to respect the
        // user interface idiom.
        // The only exception is that if the user interface idiom is Pad (so
        // the iOS app is running as 'Designed for iPad') and the current device
        // is Vision Pro. In that case we need to set the current device name as
        // 'applevision' instead of 'ipad'. For 'Designed for iPhone' iOS apps
        // running in Vision Pro devices, we should return 'iphone'.
        let currentDevice = UIDevice.current
        if currentDevice.userInterfaceIdiom == .pad {
            return isiOSAppOnVision() ? DEVICE_NAME_VISION : DEVICE_NAME_IPAD
        }
        else {
            return currentDevice.model.hasPrefix("iPod") ? DEVICE_NAME_IPOD : DEVICE_NAME_IPHONE
        }
#elseif os(macOS)
        return DEVICE_NAME_MAC
#elseif os(watchOS)
        return DEVICE_NAME_WATCH
#elseif os(visionOS)
        return DEVICE_NAME_VISION
#elseif os(tvOS)
        return DEVICE_NAME_APPLETV
#else
        return DEVICE_NAME_OTHER
#endif
    }

    /// Extract and generate (if needed) the rule that the collection of XML plural tags from the plural string
    /// contains.
    ///
    /// - Parameters:
    ///   - pluralString: The plural string containing a number of XML plural tags.
    ///   - deviceName: The device name (optional).
    /// - Returns: The final rule to be used, nil if there was an error.
    public class func extract(pluralString: String,
                              deviceName: String = currentDeviceName()) -> String? {
        return self.init(pluralString: pluralString)?.extract(deviceName)
    }
}

extension XMLPluralParser : XMLParserDelegate {
    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?,
                attributes attributeDict: [String : String] = [:]) {
        guard elementName == TXNative.CDS_XML_TAG_NAME,
            let id = attributeDict[TXNative.CDS_XML_ID_ATTRIBUTE] else {
            return
        }

        pendingCDSUnitID = id
        pendingString = ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        guard let cdsUnitID = pendingCDSUnitID else {
            return
        }
        parsedResults[cdsUnitID] = pendingString
        pendingCDSUnitID = nil
        pendingString = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard let _ = pendingCDSUnitID else {
            return
        }
        pendingString += string
    }
}

/// Utility class that allows SDK clients to leverage the logic used for pluralization rules.
public final class PluralUtils {
    private static let SUBSTITUTION_TOKEN_PATTERN = #"%\d*\$*#@[^@]+@"#
    private static let CDS_XML_TOKEN_DELIMITER = "@"

    /// For a given substitutions phrase, it returns an array with the parsed tokens.
    ///
    /// ## String Catalogs (`.xcstrings`)
    /// ```
    /// This iPhone contains %1$#@token1@ with %2$#@token2@
    /// ```
    /// The extracted tokens will be:
    /// * `("%1$#@token1@", "1$", "token1")`
    /// * `("%2$#@token2@", "2$", "token2")`
    ///
    /// ## Strings Dictionary Files (`.stringsdict`)
    /// ```
    /// This iPhone contains %#@token1@ with %#@token2@
    /// ```
    /// The extracted tokens will be: 
    /// * `("%#@token1@", "", "token1")`
    /// * `("%#@token2@", "", "token2")`
    ///
    /// - Parameter substitutionsPhrase: The substitutions phrase
    /// - Returns: The array of extracted token tuples. A tuple of three elements: The first one is the
    /// original token, the second is the exported prefix (positional specifier) and the cleaned up version of
    /// the token without the specifiers and the delimiters.
    public class func extractTokens(from substitutionsPhrase: String) -> [(String, String, String)] {
        // Bail fast if no token prefix is found.
        guard substitutionsPhrase.contains("#@") else {
            return []
        }

        // Extract the ICU rules from the strings
        var regex: NSRegularExpression

        do {
            regex = try NSRegularExpression(pattern: Self.SUBSTITUTION_TOKEN_PATTERN,
                                            options: [])
        }
        catch {
            return []
        }

        var tokens: [(String, String, String)] = []

        regex
            .matches(in: substitutionsPhrase,
                      options: [],
                      range: NSRange(location: 0,
                                     length: substitutionsPhrase.count))
            .forEach {
                let tokenRange = $0.range(at: 0)
                guard !NSEqualRanges(tokenRange, NSMakeRange(NSNotFound, 0)) else {
                    return
                }
                let token = (substitutionsPhrase as NSString).substring(with: tokenRange)
                if let processedTokenResult = process(token: token) {
                    tokens.append(processedTokenResult)
                }
            }

        return tokens
    }

    /// Processes a token, exposing certain of its parameters
    ///
    /// - Parameter token: The input token to be processed.
    /// - Returns: A tuple of three elements: The first one is the original token, the second is the
    /// exported prefix (positional specifier) and the cleaned up version of the token without the specifiers
    /// and the delimiters.
    private class func process(token: String) -> (String, String, String)? {
        let tokenComponents = token.components(separatedBy: CDS_XML_TOKEN_DELIMITER)
        guard tokenComponents.count == 3 else {
            return nil
        }
        // Token prefix should be:
        // * XCStrings: "1$", "2$", ...
        // * Strings Dict: ""
        let tokenPrefix = String(tokenComponents[0].dropFirst().dropLast())
        // Cleaned tokens should be "token1", "token2", etc
        let cleanedToken = tokenComponents[1]
        return (token, tokenPrefix, cleanedToken)
    }

    /// Wraps the provided token with the proper delimiters and with the specified prefix, preparing it for
    /// placement in the intermediate ICU rule.
    ///
    /// - Parameters:
    ///   - tokenPrefix: The prefix of the token.
    ///   - token: The actual token to be wrapped.
    /// - Returns: The final wrapped token.
    fileprivate class func buildToken(with tokenPrefix: String,
                                 token: String) -> String {
        return "%\(tokenPrefix)#\(CDS_XML_TOKEN_DELIMITER)\(token)\(CDS_XML_TOKEN_DELIMITER)"
    }
}
