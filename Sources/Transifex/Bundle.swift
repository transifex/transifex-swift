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

        Logger.verbose("Generating custom bundle at \(tempURL)")

        let fileManager = FileManager.default

        // Create the downloaded bundle in a temp url and then replace the
        // existing one once the generation has been successful.
        try fileManager.createDirectory(at: tempURL,
                                        withIntermediateDirectories: true)

        // Generate an Info.plist for the bundle
        var bundleLocalizations: [String] = []
        translations.forEach { (localeKey, strings) in
            bundleLocalizations.append("\t<string>\(localeKey)</string>")
        }

        let infoPlistContents = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.transifex.tx.custombundle</string>
    <key>CFBundleName</key>
    <string>TX Custom Bundle</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>\(sourceLocale)</string>
    <key>CFBundlePackageType</key>
    <string>BNDL</string>
    <key>CFBundleVersion</key>
    <string>6.0</string>
    <key>CFBundleLocalizations</key>
    <array>
\(bundleLocalizations.joined(separator: "\n"))
    </array>
</dict>
</plist>
"""
        let infoPlistPath = tempURL.appendingPathComponent("Info.plist")
        try infoPlistContents.write(to: infoPlistPath,
                                    atomically: true,
                                    encoding: .utf8)

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
            var xmlPlurals: [String: [String: String]] = [:]
            var icuPlurals: [String: [String: ICUPluralResult]] = [:]

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
            if nonPlurals.count > 0 {
                let tableName = "Localizable"
                let stringsPath = lProj.appendingPathComponent("\(tableName).strings")

                let stringsContent = nonPlurals
                    .sorted { $0.key < $1.key }
                    .map { "\"\($0)\" = \"\($1)\";" }
                    .joined(separator: "\n")

                try stringsContent.write(to: stringsPath,
                                         atomically: true,
                                         encoding: .utf8)
            }

            // Generate `.stringsdict` file(s)
            //
            // TODO: Pluralization / Device Variations / Substitutions
            //
            // Process ICU and XML plurals and create the respective
            // pluralization `.stringsdict` file.
            if icuPlurals.count > 0 {
                Logger.verbose("icuPlurals: \(icuPlurals)")
            }
            if xmlPlurals.count > 0 {
                Logger.verbose("xmlPlurals: \(xmlPlurals)")
            }
        }

        let finalURL = directoryURL
            .appendingPathComponent(Self.BUNDLE_FILENAME,
                                    isDirectory: true)

        Logger.verbose("Replacing \(finalURL) contents with contents from \(tempURL)")

        return try fileManager.replaceItemAt(finalURL,
                                             withItemAt: tempURL)
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

    /// Points to the custom Transifex bundle generated after downloading the translations from CDS.
    private static func downloaded(groupIdentifier: String?) -> Bundle? {
        guard let url = URL.downloadFolderURL(groupIdentifier: groupIdentifier)?
            .appendingPathComponent(BUNDLE_FILENAME, isDirectory: true) else {
            return nil
        }

        return Bundle(url: url)
    }
}
