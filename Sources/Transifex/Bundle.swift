//
//  Bundle.swift
//  transifex
//
//  Created by Stelios Petrakis on 18.04.25.
//

import Foundation

enum TXBundleErrors: Error {
    case invalidBundleURL
}

public class TXBundle {
    /// The filename of the constructed transifex bundle
    private static let BUNDLE_FILENAME = "tx.bundle"

    private static let VALUE_PLACEHOLDER = "value"
    private static let VALUE_FORMAT_PLACEHOLDER = "%#@\(VALUE_PLACEHOLDER)@"

    private var groupIdentifier: String?
    private var sourceLocale: String

    /// The underlying `.bundle` container computed during initialization. It points to either the
    /// downloaded generated bundle or the generated bundle add by the developer in-app, giving priority
    /// to the former.
    internal private(set) var underlyingBundle: Bundle?

    /// Initializes the `TXBundle` with a specific group identifier provided by the developer.
    ///
    /// - Parameter groupIdentifier: The application group identifier provided by the developer
    /// during the SDK initialization.
    internal init(groupIdentifier: String?,
                  sourceLocale: String) {
        self.groupIdentifier = groupIdentifier
        self.sourceLocale = sourceLocale
        // Calculate the custom bundle to be provided to the developer during
        // initialization.
        self.underlyingBundle = Self.downloaded(groupIdentifier: groupIdentifier) ?? Self.bundled
    }

    /// Generates the custom transifex bundle container from the provided translations, overriding the
    /// existing bundle, if it already exists.
    ///
    /// - Parameters:
    ///   - translations: Translations structure
    ///   - groupIdentifier: Optional group identifier of the application so that the bundle container
    ///   is stored in a folder accessible from all different application extensions.
    internal func generateDownloaded(with translations: TXTranslations) throws {
        guard let downloadedFolderURL = URL
            .downloadFolderURL(groupIdentifier: groupIdentifier) else {
            throw TXBundleErrors.invalidBundleURL
        }

#if os(macOS)
        let isMacOS = true
#else
        let isMacOS = false
#endif

        _ = try Self.generateCustomBundle(with: translations,
                                          sourceLocale: sourceLocale,
                                          at: downloadedFolderURL,
                                          isMacOS: isMacOS)
    }

    // MARK: - Public

    /// Generates the custom bundle with the provided translations to the specified file URL.
    /// 
    /// - Parameters:
    ///   - translations: The translations to be included in the custom bundle.
    ///   - sourceLocale: The source locale identifier (e.g. "en")
    ///   - directoryURL: The file system directory url pointing to the generated custom bundle.
    ///   - isMacOS: Whether the generation should produce a custom bundle for a MacOS target.
    /// - Returns: The output url where the custom bundle container has been generated at.
    public static func generateCustomBundle(with translations: TXTranslations,
                                            sourceLocale: String,
                                            at directoryURL: URL,
                                            isMacOS: Bool) throws -> URL? {
        let tempURL = directoryURL
            .appendingPathComponent("\(UUID().uuidString).bundle",
                                    isDirectory: true)

        Logger.verbose("Generating custom bundle at \(tempURL.path)")

        let fileManager = FileManager.default

        // Create the downloaded bundle in a temp url and then replace the
        // existing one once the generation has been successful.
        try fileManager.createDirectory(at: tempURL,
                                        withIntermediateDirectories: true)

        // Generate an Info.plist for the bundle
        var plistDict: [String: Any] = [:]
        plistDict["CFBundleIdentifier"] = "com.transifex.tx.custombundle"
        plistDict["CFBundleName"] = "TX Custom Bundle"
        plistDict["CFBundleDevelopmentRegion"] = sourceLocale
        plistDict["CFBundlePackageType"] = "BNDL"
        plistDict["CFBundleVersion"] = "6.0"
        plistDict["CFBundleLocalizations"] = translations.map { $0.key }

        let plistData = try PropertyListSerialization.data(fromPropertyList: plistDict,
                                                           format: .xml,
                                                           options: 0)
        let infoPlistURL = tempURL.appendingPathComponent("Info.plist")
        try plistData.write(to: infoPlistURL)

        var lProjParentDirectory = tempURL

        // NOTE: For MacOS apps we need to store the `.lproj` directories within
        // the `Resources` directory of the generated bundle.
        //
        // Ref: https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/BundleTypes/BundleTypes.html#//apple_ref/doc/uid/20001119-105003
        if isMacOS {
            let resourcesDirectory = tempURL.appendingPathComponent("Resources",
                                                                    isDirectory: true)

            try fileManager.createDirectory(at: resourcesDirectory,
                                            withIntermediateDirectories: true)

            lProjParentDirectory = resourcesDirectory
        }

        try translations.forEach { (localeKey, strings) in
            let lProj = lProjParentDirectory.appendingPathComponent("\(localeKey).lproj")

            try fileManager.createDirectory(at: lProj,
                                            withIntermediateDirectories: true)

            // TODO: Custom Localization Tables
            //
            // Fetch the occurrences metadata information for each source string
            // from CDS (implementation pending) and use that to generate the
            // correct `tableName` below.

            var nonPlurals: [String: String] = [:]
            var icuPlurals: [String: [String: ICUPluralResult]] = [:]
            var xmlPlurals: [String: [String: String]] = [:]

            strings.forEach { (stringKey, stringInfo) in
                guard let sourceString = stringInfo[TXDecoratorCache.STRING_KEY] else {
                    return
                }

                // Detect if the string begins with the CDS root XML tag:
                // `<cds-root>`
                if (sourceString.hasPrefix("<\(TXNative.CDS_XML_ROOT_TAG_NAME)>")) {
                    if let parsedResults = XMLPluralParser.parse(pluralString: sourceString) {
                        xmlPlurals[stringKey] = parsedResults
                    }
                }
                else {
                    // Distinguish plural from non-plural content.
                    let plurals = sourceString.extractICUPlurals()

                    if plurals.count > 0 {
                        icuPlurals[stringKey] = plurals
                    }
                    else {
                        nonPlurals[stringKey] = sourceString
                    }
                }
            }

            // Generate `.strings` file(s)
            try generateStrings(nonPlurals: nonPlurals,
                                in: lProj)

            // Generate `.stringsdict` file(s)
            //
            // Process ICU and XML plurals and create the respective
            // pluralization `.stringsdict` file.
            try generateStringsDict(icuPlurals: icuPlurals,
                                    xmlPlurals: xmlPlurals,
                                    in: lProj)
        }

        let finalURL = directoryURL
            .appendingPathComponent(Self.BUNDLE_FILENAME,
                                    isDirectory: true)

        Logger.verbose("Replacing \(finalURL.path) contents with contents from \(tempURL.path)")

        return try fileManager.replaceItemAt(finalURL,
                                             withItemAt: tempURL)
    }

    // MARK: - Private

    /// Generate the `.strings` file from the provided non-pluralized localized strings.
    ///
    /// - Parameters:
    ///   - nonPlurals: The dictionary containing the non-pluralized strings.
    ///   - directory: The directory to store the generated `.strings` file.
    private static func generateStrings(nonPlurals: [String: String],
                                        in directory: URL) throws {
        guard nonPlurals.count > 0 else {
            return
        }

        let tableName = "Localizable"
        let stringsPath = directory.appendingPathComponent("\(tableName).strings")

        let stringsContent = nonPlurals
            .sorted { $0.key < $1.key }
            .map { "\"\($0)\" = \"\($1)\";" }
            .joined(separator: "\n")

        try stringsContent.write(to: stringsPath,
                                 atomically: true,
                                 encoding: .utf8)
    }

    /// Generate the `.stringsdict` file from the provided pluralized localized strings (both ICU and
    /// XML formats).
    ///
    /// - Parameters:
    ///   - icuPlurals: The dictionary containing the ICU pluralized strings (simple pluralization).
    ///   - xmlPlurals: The dictionary containing the XML pluralized strings (device variations,
    ///   substitutions, complex rules).
    ///   - directory: The directory to store the generated `.strings` file.
    private static func generateStringsDict(icuPlurals: [String: [String: ICUPluralResult]],
                                            xmlPlurals: [String: [String: String]],
                                            in directory: URL) throws {
        guard icuPlurals.count > 0 || xmlPlurals.count > 0 else {
            return
        }

        let tableName = "Localizable"
        let stringsDictURL = directory.appendingPathComponent("\(tableName).stringsdict")

        var stringsDict: [String: Any] = [:]

        icuPlurals
            .sorted { $0.key < $1.key }
            .forEach { (key, value) in
            // Multiple ICU plurals are not supported. For that we use
            // the XML plurals (substitutions)
            guard let icuPluralResult = value.first?.value else {
                return
            }

            guard let extractedType = icuPluralResult.extractedPlurals
                .compactMap({ $1.extractFormatSpecifierType() }).first else {
                return
            }

            var icuPluralOuterDict: [String: Any] = [:]
            icuPluralOuterDict.addLocalizedFormatKey(VALUE_FORMAT_PLACEHOLDER)

            var icuPluralInnerDict: [String: Any] = [:]
            icuPluralInnerDict.addFormatSpecPlural()
            icuPluralInnerDict.addFormatValueType(extractedType)

            icuPluralResult.extractedPlurals
                .sorted { $0.key.rawValue < $1.key.rawValue }
                .forEach { (key, value) in
                icuPluralInnerDict[key] = value
            }

            icuPluralOuterDict[VALUE_PLACEHOLDER] = icuPluralInnerDict

            stringsDict[key] = icuPluralOuterDict
        }

        xmlPlurals
            .sorted { $0.key < $1.key }
            .forEach { (key: String, value: [String : String]) in
            var xmlPluralOuterDict: [String: Any] = [:]

            if let mainPhrase = value[XMLPluralParser.CDS_XML_ID_ATTRIBUTE_SUBSTITUTIONS_TOKEN] {
                xmlPluralOuterDict.addLocalizedFormatKey(mainPhrase)

                let tokens = PluralUtils.extractTokens(from: mainPhrase)

                Self.generateSubstitutionsXMLRepresentation(tokens: tokens,
                                                            with: value,
                                                            in: &xmlPluralOuterDict)
            }
            else if XMLPluralParser.containsDeviceRules(value) {
                // Filter only the rules that begin with "device."
                let deviceRulePrefix = XMLPluralParser.deviceRule()
                let deviceRules = value.keys.filter {
                    $0.starts(with: deviceRulePrefix)
                }
                // Collect all unique device names from the filtered rules
                let deviceNames = Set(deviceRules.compactMap {
                    $0.components(separatedBy: XMLPluralParser.CDS_XML_ID_ATTRIBUTE_DELIMITER)[1]
                })

                if deviceNames.count > 0 {
                    var xmlPluralInnerDict: [String: Any] = [:]

                    deviceNames
                        .sorted()
                        .forEach { deviceName in
                        if let deviceValue = value[deviceRulePrefix + deviceName] {
                            let tokens = PluralUtils.extractTokens(from: deviceValue)

                            // Substitutions inside a device rule
                            if tokens.count > 0 {
                                var xmlDeviceOuterDict: [String: Any] = [:]
                                xmlDeviceOuterDict.addLocalizedFormatKey(deviceValue)

                                Self.generateSubstitutionsXMLRepresentation(tokens: tokens,
                                                                            with: value,
                                                                            in: &xmlDeviceOuterDict)

                                xmlPluralInnerDict[deviceName] = xmlDeviceOuterDict
                            }
                            // Simple device rule
                            else {
                                xmlPluralInnerDict[deviceName] = deviceValue
                            }
                        }
                        else {
                            // Plurals inside a device rule
                            var xmlDeviceOuterDict: [String: Any] = [:]

                            let pluralRules = XMLPluralParser.parsePluralRules(value,
                                firstExpectedComponent: XMLPluralParser.CDS_XML_ID_ATTRIBUTE_DEVICE_TOKEN,
                                secondExpectedComponent: deviceName)

                            guard let extractedType = pluralRules
                                .compactMap({ $1.extractFormatSpecifierType() }).first else {
                                return
                            }

                            xmlDeviceOuterDict.addLocalizedFormatKey(VALUE_FORMAT_PLACEHOLDER)

                            var xmlDeviceInnerDict: [String: Any] = [:]
                            xmlDeviceInnerDict.addFormatSpecPlural()
                            xmlDeviceInnerDict.addFormatValueType(extractedType)

                            pluralRules.forEach { (key, value) in
                                xmlDeviceInnerDict[key] = value
                            }

                            xmlDeviceOuterDict[VALUE_PLACEHOLDER] = xmlDeviceInnerDict

                            xmlPluralInnerDict[deviceName] = xmlDeviceOuterDict
                        }
                    }

                    xmlPluralOuterDict.addDeviceSpecificRule(xmlPluralInnerDict)
                }
            }

            stringsDict[key] = xmlPluralOuterDict
        }

        let plistData = try PropertyListSerialization.data(fromPropertyList: stringsDict,
                                                           format: .xml,
                                                           options: 0)
        try plistData.write(to: stringsDictURL)
    }

    /// Generates the `.stringsdict` XML representation of the plural rules for a substitution either
    /// for a specific device or generally
    ///
    /// - Parameters:
    ///   - tokens: The array containing all the extracted token representations
    ///   - pluralRules: The dictionary containing the plural rules for the substitution
    ///   - dict: The dictionary that will contain the generated plural rules
    private static func generateSubstitutionsXMLRepresentation(tokens: [PluralUtils.TXToken],
                                                               with pluralRules: [String : String],
                                                               in dict: inout [String: Any]) {
        tokens.forEach { processedTokenResult in
            // Token prefix should be: "1$", "2$", ...
            let tokenPrefix = processedTokenResult.1
            // Cleaned tokens should be: "token1", "token2", ...
            let cleanedToken = processedTokenResult.2
            let pluralRules = XMLPluralParser.parsePluralRules(pluralRules,
                firstExpectedComponent: XMLPluralParser.CDS_XML_ID_ATTRIBUTE_SUBSTITUTIONS_TOKEN,
                secondExpectedComponent: cleanedToken)

            guard let extractedType = pluralRules
                .compactMap({ $1.extractFormatSpecifierType() }).first else {
                return
            }

            var xmlPluralInnerDict: [String: Any] = [:]
            xmlPluralInnerDict.addFormatSpecPlural()
            xmlPluralInnerDict.addFormatValueType(extractedType)

            pluralRules .forEach { (key, value) in
                // Ensure that the pluralized value will include the positional
                // specifier
                let normalizedValue = value.replacingOccurrences(of: "%\(extractedType)",
                                                                 with: "%\(tokenPrefix)\(extractedType)")
                xmlPluralInnerDict[key] = normalizedValue
            }

            dict[cleanedToken] = xmlPluralInnerDict
        }
    }

    /// Points to the custom Transifex bundle generated after downloading the translations from CDS.
    private static func downloaded(groupIdentifier: String?) -> Bundle? {
        guard let url = URL.downloadFolderURL(groupIdentifier: groupIdentifier)?
            .appendingPathComponent(BUNDLE_FILENAME, isDirectory: true) else {
            return nil
        }

        return Bundle(url: url)
    }

    /// Points to the custom Transifex bundle provided by the developer within the app.
    private static var bundled: Bundle? {
        let resourceComps = BUNDLE_FILENAME.split(separator: ".")

        guard resourceComps.count == 2 else {
            return nil
        }

        let resourceName = String(resourceComps[0])
        let resourceExtension = String(resourceComps[1])

        guard let url = Bundle.application.url(forResource: resourceName,
                                               withExtension: resourceExtension) else {
            return nil
        }

        return Bundle(url: url)
    }
}
