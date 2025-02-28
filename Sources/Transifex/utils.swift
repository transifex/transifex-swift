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

@available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
extension String.LocalizationValue {
    /// Struct containing the extracted key and arguments of the `LocalizationValue`
    internal struct ExtractedLocalizationValue {
        var key: String
        var args: [Any]

        /// Combines the extracted `arguments` with the `replacements` array from the
        /// `String.LocalizationOptions` struct.
        ///
        /// - Parameter options: The options structure.
        /// - Returns: The combined arguments where placeholder elements have been replaced
        /// with the replacement values.
        @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
        func combinedArgs(with options: String.LocalizationOptions?) -> [Any] {
            // The replacements array must exist.
            guard var replacements = options?.replacements else {
                return args
            }

            // The replacements array must have a size equal to the number of
            // placeholder elements in the extracted args array.
            guard args
                .filter({ $0 is String.LocalizationValue.Placeholder })
                .count == replacements.count else {
                return args
            }

            var combinedArgs: [Any] = []

            args.forEach { arg in
                // Add the non-placeholder elements
                guard arg is String.LocalizationValue.Placeholder else {
                    combinedArgs.append(arg)
                    return
                }
                // Given the 2nd guard statement, that shouldn't happen but
                // it's here as a sanity check.
                guard let firstReplacement = replacements.first else {
                    combinedArgs.append(arg)
                    return
                }
                // Add the first replacement and remove it.
                //
                // NOTE: We may also want to check if the placeholderArg enum
                // value matches the type of the firstReplacement object.
                //
                combinedArgs.append(firstReplacement)
                replacements.removeFirst()
            }

            return combinedArgs
        }
    }

    // The extraction to be performed: Reflection or Regular expression
    public enum ExtractionType {
        case reflection
        case regex
    }

    // Default key value to be used when key extraction fails.
    private static let EXTRACTION_FAILED_KEY = "extraction_failed"

    /// Extract the underlying `key` and `arguments` of the `LocalizationValue` struct using
    /// either reflection (default) or regular expression.
    ///
    /// If the properties cannot be extracted, the `key` will be the `extraction_failed` string and the
    /// `arguments` array will be empty.
    ///
    /// - Parameter extractionType: The extraction type (reflection or regular expression).
    /// - Returns: The extracted location value.
    internal func extract(_ extractionType: ExtractionType = .reflection) -> ExtractedLocalizationValue {
        /// The reflection logic assumes the following internal structure for the `LocalizationValue`
        /// struct:
        /// - key (String)
        /// - arguments (Array of LocalizationValue.FormatArgument.Storage)
        ///   - storage
        ///     - value or String.LocalizationValue.Placeholder
        switch extractionType {
        case .reflection:
            return ExtractedLocalizationValue(key: extractKeyReflection() ?? Self.EXTRACTION_FAILED_KEY,
                                              args: extractArgumentsReflection())
        case .regex:
            return ExtractedLocalizationValue(key: extractKeyRegex() ?? Self.EXTRACTION_FAILED_KEY,
                                              args: extractArgumentsRegex())
        }
    }

    // MARK: Reflection
    private static let MIRROR_LABEL_KEY = "key"
    private static let MIRROR_LABEL_ARGS = "arguments"
    private static let MIRROR_LABEL_STORAGE = "storage"
    private static let MIRROR_LABEL_VALUE = "value"
    private static let MIRROR_LABEL_PLACEHOLDER = "placeholder"

    /// Extracts the key from the `LocalizationValue` using reflection.
    ///
    /// - Returns: The extracted key or `nil`.
    private func extractKeyReflection() -> String? {
        return Mirror(reflecting: self)
            .children
            .first(where: { $0.label == Self.MIRROR_LABEL_KEY })?
            .value as? String
    }

    /// Extract the arguments from the `LocalizationValue` using reflection.
    ///
    /// - Returns: The extracted arguments or an empty array.
    private func extractArgumentsReflection() -> [Any] {
        var localizationValueArguments: [Any] = []

        if let args = Mirror(reflecting: self)
            .children
            .first(where: { $0.label == Self.MIRROR_LABEL_ARGS })?
            .value as? [Any] {
            args.forEach { arg in
                if let storage = Mirror(reflecting: arg)
                    .children
                    .first(where: { $0.label == Self.MIRROR_LABEL_STORAGE })?
                    .value {
                    if let value = Mirror(reflecting: storage)
                        .children
                        .first(where: { $0.label == Self.MIRROR_LABEL_VALUE })?
                        .value {
                        if let intValue = value as? Int {
                            localizationValueArguments.append(intValue as CVarArg)
                        } else if let uintValue = value as? UInt {
                            localizationValueArguments.append(uintValue as CVarArg)
                        } else if let floatValue = value as? Float {
                            localizationValueArguments.append(floatValue as CVarArg)
                        } else if let doubleValue = value as? Double {
                            localizationValueArguments.append(doubleValue as CVarArg)
                        } else if let valueVarArg = value as? CVarArg {
                            localizationValueArguments.append(valueVarArg)
                        }
                        return
                    }
    #if os(iOS)
                    if #available(iOS 16, *),
                        let placeholder = extractPlaceholderReflection(storage) {
                        localizationValueArguments.append(placeholder)
                    }
    #elseif os(watchOS)
                    if #available(watchOS 9, *),
                        let placeholder = extractPlaceholderReflection(storage) {
                        localizationValueArguments.append(placeholder)
                    }
    #elseif os(tvOS)
                    if #available(tvOS 16, *),
                        let placeholder = extractPlaceholderReflection(storage) {
                        localizationValueArguments.append(placeholder)
                    }
    #elseif os(macOS)
                    if #available(macOS 13, *),
                        let placeholder = extractPlaceholderReflection(storage) {
                        localizationValueArguments.append(placeholder)
                    }
    #endif
                }
            }
        }

        return localizationValueArguments
    }

    /// Extract the underlying LocalizationValue.Placeholder enum from a storage property using reflection.
    ///
    /// - Parameter storage: The storage property
    /// - Returns: The LocalizationValue.Placeholder enum value, `nil` if extraction is not possible.
    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    private func extractPlaceholderReflection(_ storage: Any) -> String.LocalizationValue.Placeholder? {
        return Mirror(reflecting: storage)
            .children
            .first(where: { $0.label == Self.MIRROR_LABEL_PLACEHOLDER})?
            .value as? String.LocalizationValue.Placeholder
    }

    // MARK: Regular expression
    private static let KEY_REGEX = #"key:\s*"([^"]*)""#
    private static let ARGUMENTS_REGEX = #"(value|placeholder)\(([^)]+)\)"#

    private static let ARGUMENTS_REPLACE_1 = "(extension in Foundation):Swift.String.LocalizationValue.FormatArgument(storage: (extension in Foundation):Swift.String.LocalizationValue.FormatArgument.Storage."
    private static let ARGUMENTS_REPLACE_2 = "(extension in Foundation):Swift.String.LocalizationValue.Placeholder."

    private static let ARGUMENTS_VALUE = "value"
    private static let ARGUMENTS_PLACEHOLDER = "placeholder"

    /// Extract the key from the LocalizationValue description using a regular expression.
    ///
    /// - Returns: The extracted key or `nil`.
    private func extractKeyRegex() -> String? {
        let input = "\(self)"
        return (try? NSRegularExpression(pattern: Self.KEY_REGEX))
            .flatMap { $0.firstMatch(in: input,
                                     range: NSRange(input.startIndex...,
                                                    in: input)) }
            .flatMap { Range($0.range(at: 1),
                             in: input) }
            .map { String(input[$0]) }
    }

    /// Extract the arguments from the LocalizationValue description using a regular expression.
    ///
    /// - Returns: The extracted arguments or an empty array.
    private func extractArgumentsRegex() -> [Any] {
        var extractedArgs: [Any] = []

        let input = "\(self)"
            .replacingOccurrences(of: Self.ARGUMENTS_REPLACE_1, with: "")
            .replacingOccurrences(of: Self.ARGUMENTS_REPLACE_2, with: "")
            .replacingOccurrences(of: "))", with: ")")

        do {
            let regex = try NSRegularExpression(pattern: Self.ARGUMENTS_REGEX)
            let matches = regex.matches(in: input, range: NSRange(input.startIndex..., in: input))

            for match in matches {
                guard let typeRange = Range(match.range(at: 1), in: input),
                      let valueRange = Range(match.range(at: 2), in: input) else { continue }

                let type = String(input[typeRange])
                var extractedValue = String(input[valueRange])

                if type == Self.ARGUMENTS_VALUE {
                    if let intValue = Int(extractedValue) {
                        extractedArgs.append(intValue as CVarArg)
                    } else if let uintValue = UInt(extractedValue) {
                        extractedArgs.append(uintValue as CVarArg)
                    } else if let floatValue = Float(extractedValue) {
                        extractedArgs.append(floatValue as CVarArg)
                    } else if let doubleValue = Double(extractedValue) {
                        extractedArgs.append(doubleValue as CVarArg)
                    } else {
                        // Remove surrounding quotes if present
                        extractedValue = extractedValue.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        extractedArgs.append(extractedValue as CVarArg)
                    }
                } else if type == Self.ARGUMENTS_PLACEHOLDER {
#if os(iOS)
                    if #available(iOS 16, *),
                       let placeholder = extractPlaceholderRegex(extractedValue) {
                        extractedArgs.append(placeholder)
                    }
#elseif os(watchOS)
                    if #available(watchOS 9, *),
                       let placeholder = extractPlaceholderRegex(extractedValue) {
                        extractedArgs.append(placeholder)
                    }
#elseif os(tvOS)
                    if #available(tvOS 16, *),
                       let placeholder = extractPlaceholderRegex(extractedValue) {
                        extractedArgs.append(placeholder)
                    }
#elseif os(macOS)
                    if #available(macOS 13, *),
                       let placeholder = extractPlaceholderRegex(extractedValue) {
                        extractedArgs.append(placeholder)
                    }
#endif
                }
            }
        } catch {
            // no-op
        }

        return extractedArgs
    }

    /// Cast the provided string value to String.LocalizationValue.Placeholder if possible
    ///
    /// - Parameter value: The string value corresponding to a Placeholder enum value.
    /// - Returns: The LocalizationValue.Placeholder enum value, `nil` if extraction is not possible.
    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    private func extractPlaceholderRegex(_ value: String) -> String.LocalizationValue.Placeholder? {
        switch value {
        case "object":
            return String.LocalizationValue.Placeholder.object
        case "int":
            return String.LocalizationValue.Placeholder.int
        case "uint":
            return String.LocalizationValue.Placeholder.uint
        case "float":
            return String.LocalizationValue.Placeholder.float
        case "double":
            return String.LocalizationValue.Placeholder.double
        default:
            return nil
        }
    }
}

extension Bundle {
    /// Return a Bundle instance based on the value of the
    /// `LocalizedStringResource.BundleDescription` enum.
    ///
    /// - Parameter description: The `LocalizedStringResource.BundleDescription`
    /// enum value.
    /// - Returns: The `Bundle` instance, `nil` if it cannot be constructed.
    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    internal static func from(description: LocalizedStringResource.BundleDescription) -> Bundle? {
        switch description {
        case .atURL(let url):
            return Bundle(url: url)
        case .forClass(let aClass):
            return Bundle(for: aClass)
        case .main:
            return Bundle.main
        @unknown default:
            return nil
        }
    }
}
