//
//  Cache.swift
//  Transifex
//
//  Created by Dimitrios Bendilas on 17/7/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

/// Structure that represents a translated string.
///
/// Format: "string" : {The translated string}
public typealias TXStringInfo = [String: String]

/// Structure that represents translated strings with their respective string keys.
///
/// Format: {string key} : {TXStringInfo}
public typealias TXLocaleStrings = [String: TXStringInfo]

/// Structure that represents all of the translated string of an app for the specified app locales.
///
/// Format: {locale code} : {TXLocaleStrings}
public typealias TXTranslations = [String: TXLocaleStrings]

extension String {
    /// Given an optional translated string, returns whether that string contains a translation or not.
    ///
    /// In order for a string to be considered a translation, it has to be not nil and not being an empty string.
    ///
    /// - Parameter string: The string to be checked
    /// - Returns: True if the string contains a translation, False otherwise.
    static func containsTranslation(_ string: String?) -> Bool {
        guard let string = string else {
            return false
        }
    
        return string.count > 0
    }
}

/// Update policy that specifies the way that the internal cache is updated with new translations.
///
/// You can find an easy to understand table containing a number of cases and how each policy updates the
/// cache below:
///
///```
/// | Key || Cache | New  || Replace All   | Update using Translated        |
/// |-----||-------|------||---------------|--------------------------------|
/// | a   || "a"   | -    || -             | "a"                            |
/// | b   || "b"   | "B"  || "B"           | "B"                            |
/// | c   || "c"   | ""   || ""            | "c"                            |
/// | d   || ""    | -    || -             | ""                             |
/// | e   || ""    | "E"  || "E"           | "E"                            |
/// | f   || -     | "F"  || "F"           | "F"                            |
/// | g   || -     | ""   || ""            | -                              |
///```
///
/// Here's an example on how to read the table above:
///
/// * Given a string with `key="c"`
/// * and a cache that has `"c"` as the stored value for this key (`"c" -> "c"`)
/// * if an empty translation arrives for this string (`""`)
///     * if policy is  `.replaceAll`, then the cache will be updated so that (`"c" -> "")`
///     * in contrast to that, if policy is `.updateUsingTranslated`, then the cache will stay as is
///     (`"c" -> "c"`), because the new translation is empty.
///
/// A `"-"` value means that the respective key does not exist. For example:
///
/// * Given a string with `key="f"`
/// * and a cache that has no entry with `"f"` as a key
/// * if a translation arrives for this string (`"f" -> "F"`)
///     * if policy is `.replaceAll`, then the cache will be updated by adding a new entry so that
///     (`"f" -> "F"`)
///     * if policy is `.updateUsingTranslated`, then the same will happen, since the new translation
///     is not empty
@objc
public enum TXCacheUpdatePolicy : Int {
    /// Discards the existing cache entries completely and populates the cache with the new entries,
    /// even if they contain empty translations.
    case replaceAll
    /// Updates the existing cache with the new entries that have a non-empty translation, ignoring the rest.
    case updateUsingTranslated
}

/// A protocol for classes that act as cache for translations.
@objc
public protocol TXCache {
    /// Gets all of the translations from the cache.
    func get() -> TXTranslations
    
    /// Get the translation for a certain key and locale code pair.
    ///
    /// - Parameters:
    ///   - key: the key of the string
    ///   - localeCode: the locale code
    func get(key: String, localeCode: String) -> String?
    
    /// Update the cache with a dictionary containing locale codes as keys and a list of translations as
    /// values like this:
    ///
    /// ```
    /// {
    ///     'fr' : {
    ///          'key1' : { 'string' : '...' },
    ///          'key2' : { 'string' : '...' },
    ///     },
    ///     'de' : {
    ///          'key3' : { 'string' : '...' },
    ///     },
    ///     'gr' : {
    ///          'key4' : { 'string' : '...' },
    ///     },
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - translations: The dictionary structure of translations
    func update(translations: TXTranslations)
}

/// A protocol for classes that act as providers of cached translations (e.g. extracting them from a file)
@objc
public protocol TXCacheProvider {
    /// Returns the translations from the current cache provider.
    func getTranslations() -> TXTranslations?
}

/// Cache provider that loads translations from disk
public final class TXDiskCacheProvider: NSObject, TXCacheProvider {
    /// The translations extracted from disk after initialization.
    public let translations: TXTranslations?
    
    /// Initializes the disk cache provider with a file URL from disk synchronously.
    ///
    /// The disk cache provider expects the file to be encoded in JSON format using the `TXTranslations`
    /// data structure.
    ///
    /// - Parameter fileURL: The file url of the file that contains the translations
    @objc
    public init(fileURL: URL) {
        self.translations = TXDiskCacheProvider.load(from: fileURL)
    }
    
    /// Loads the translations from a file url, returns nil in case of an error.
    ///
    /// - Parameter fileURL: The url of the file that contains the translations
    /// - Returns: The translations or nil if there was an error
    private static func load(from fileURL: URL) -> TXTranslations? {
        Logger.verbose("Loading translations from \(fileURL)")
        
        var fileData: Data?
    
        do {
            fileData = try Data(contentsOf: fileURL)
        }
        catch {
            Logger.warning("\(#function) fileURL: \(fileURL) Data error: \(error)")
        }
        
        guard let data = fileData else {
            return nil
        }
        
        var storedTranslations: TXTranslations?

        do {
            storedTranslations = try JSONDecoder().decode(TXTranslations.self,
                                                          from: data)
        }
        catch {
            Logger.error("\(#function) fileURL: \(fileURL) Decode Error: \(error)")
            return nil
        }
        
        return storedTranslations
    }

    public func getTranslations() -> TXTranslations? {
        return translations
    }
}

/// Decorator class managing an internal class and propagating the get() and update() protocol method calls
/// to said cache.
open class TXDecoratorCache: NSObject, TXCache {
    /// Key used in the TXStringInfo dictionary
    public static let STRING_KEY = "string"

    let internalCache: TXCache
    
    /// Initializes the decorator class with a specific cache.
    ///
    /// - Parameter internalCache: The cache to be used
    @objc
    public init(internalCache: TXCache) {
        self.internalCache = internalCache
    }

    public func get() -> TXTranslations {
        return internalCache.get()
    }
    
    public func get(key: String, localeCode: String) -> String? {
        internalCache.get(key: key, localeCode: localeCode)
    }
    
    public func update(translations: TXTranslations) {
        internalCache.update(translations: translations)
    }
}

/// Decorator class responsible for storing any updates of the translations to a file url specified in the
/// constructor.
public final class TXFileOutputCacheDecorator: TXDecoratorCache {
    let fileURL: URL?
    
    /// Dispatch queue that ensures that the downloaded strings are written to a file in a serial fashion.
    let cacheQueue = DispatchQueue(label: "com.transifex.native.fileoutput")
    
    /// Initializes the decorator with a specific file url for storing the translations to the disk and an internal
    /// cache.
    ///
    /// - Parameters:
    ///   - fileURL: The file url
    ///   - internalCache: The internal cache
    @objc
    public init(fileURL: URL?,
                internalCache: TXCache) {
        self.fileURL = fileURL
        super.init(internalCache: internalCache)
    }
    
    /// Encodes the provided translations to a JSON string and writes the string to a file using the `fileURL`
    /// property of the constructor.
    ///
    /// - Parameter translations: The provided translations
    public override func update(translations: TXTranslations) {
        super.update(translations: translations)
        
        cacheQueue.async {
            guard let fileURL = self.fileURL else {
                return
            }
            
            do {
                try self.storeTranslations(translations: translations,
                                           fileURL: fileURL)
            }
            catch {
                Logger.error("\(#function) Error: \(error)")
            }
        }
    }
    
    enum StoringErrors: Error {
        case encodingFailed
    }
    
    /// Serializes passed translations and stores them in the fileURL specified in the constructor. If the
    /// directory of the file doesn't exist, the method tries to create it with all of its intermediate directories.
    ///
    /// - Parameter translations: The passed translations
    /// - Throws: The error that may occur during serialization, directory creation or file writing.
    private func storeTranslations(translations: TXTranslations,
                                   fileURL: URL) throws {
        Logger.verbose("Storing translations  to \(fileURL)")
        
        let folderURL = fileURL.deletingLastPathComponent()
        
        do {
            try FileManager.default.createDirectory(at: folderURL,
                                                    withIntermediateDirectories: true,
                                                    attributes: nil)
        }
        
        var jsonData: Data?
        
        do {
            jsonData = try JSONEncoder().encode(translations)
        }
        
        guard let serializedData = jsonData,
              let serializedTranslations = String(data: serializedData,
                                                  encoding: .utf8) else {
            throw StoringErrors.encodingFailed
        }
        
        do {
            try serializedTranslations.write(to: fileURL,
                                             atomically: true,
                                             encoding: .utf8)
        }
    }
}

/// Class that makes the internal cache read-only so that no update operations are allowed.
public final class TXReadonlyCacheDecorator: TXDecoratorCache {
    /// This method is a no-op as this cache decorator is read-only.
    ///
    /// - Parameter translations: The provided translations
    override public func update(translations: TXTranslations) {
        // No-op
    }
}

/// Composite class that accepts a number of cache providers and an internal cache.
/// The providers are then used to update the internal class in the order they are added in the providers list.
///
/// Example usage:
/// ```
/// let cache = TXProviderBasedCache(
///     providers: [
///         TXDiskCacheProvider(fileURL: firstFileURL),
///         TXDiskCacheProvider(fileURL: secondFileURL)
///     ],
///     internalCache: TXMemoryCache()
/// )
/// ```
public final class TXProviderBasedCache: TXDecoratorCache {
    /// Initializes the provider based cache with a list of cache providers and an internal cache that will be
    /// initialized with the contents of those providers.
    ///
    /// The order of the cache providers in the list is important.
    ///
    /// - Parameters:
    ///   - providers: The list of cache providers.
    ///   - internalCache: The internal cache to be used
    @objc
    public init(providers: [TXCacheProvider],
                internalCache: TXCache) {
        super.init(internalCache: internalCache)
        for provider in providers {
            if let providerTranslations = provider.getTranslations() {
                self.internalCache.update(translations: providerTranslations)
            }
        }
    }
}

/// Class responsible for updating the passed internalCache using a certain update policy defined
/// in the `TXCacheUpdatePolicy` enum. This is done by filtering any translations that are passed
/// via the `update(translations:)` call using an update policy that checks both the passed
/// translations and the internal cache state to decide whether a translation should update the internal cache
/// or not.
public final class TXStringUpdateFilterCache: TXDecoratorCache {
    let policy: TXCacheUpdatePolicy
    
    /// Initializes the cache with a certain update policy and an internal cache that will be updated
    /// according to that policy.
    /// 
    /// - Parameters:
    ///   - policy: The update policy to be used
    ///   - internalCache: The internal cache to be updated with the specified update policy
    @objc
    public init(policy: TXCacheUpdatePolicy,
                internalCache: TXCache) {
        self.policy = policy
        super.init(internalCache: internalCache)
    }
    
    /// Updates the internal cache with the provided translations using the update policy specified during
    /// initialization.
    ///
    /// - Parameter translations: The provided translations
    override public func update(translations: TXTranslations) {
        if policy == .replaceAll {
            super.update(translations: translations)
            return
        }
        
        var updatedTranslations = self.get()
    
        for (localeCode, localeTranslations) in translations {
            for (stringKey, translation) in localeTranslations {
                /// Make sure that the new entry contains a translation, otherwise don't process it.
                guard String.containsTranslation(translation[TXDecoratorCache.STRING_KEY]) == true else {
                    continue
                }

                if updatedTranslations[localeCode] == nil {
                    updatedTranslations[localeCode] = [:]
                }

                updatedTranslations[localeCode]?[stringKey] = translation
            }
        }

        super.update(translations: updatedTranslations)
    }
}

/// The standard cache that the TXNative SDK is initialized with, if no other cache is provided.
///
/// The cache gets initialized using the decorators implemented in the Caches.swift file of the SDK so that it
/// reads from any existing translation files either from the app bundle or the app sandbox. The cache is also
/// responsible for creating or updating the sandbox file with new translations when they will become available
/// and it offers  a memory cache for retrieving such translations so that they can be displayed in the UI.
public final class TXStandardCache: NSObject {
    /// Initializes and returns the cache using a specific update policy and an optional group identifier based
    /// on the architecture of the application that uses the SDK.
    ///
    /// - Parameters:
    ///   - updatePolicy: The specific update policy to be used when updating the internal
    ///   memory cache with the stored contents from disk. Defaults to .replaceAll.
    ///   - groupIdentifier: The group identifier of the app, if the app makes use of the app groups
    /// entitlement. Defaults to nil.
    public static func getCache(updatePolicy: TXCacheUpdatePolicy = .replaceAll,
                                groupIdentifier: String? = nil) -> TXCache {
        var providers: [TXCacheProvider] = []
        
        if let bundleURL = TXStandardCache.bundleURL() {
            Logger.verbose("Translations bundle url: \(bundleURL)")
            providers.append(TXDiskCacheProvider(fileURL: bundleURL))
        }
        
        let downloadURL = TXStandardCache.downloadURL(groupIdentifier: groupIdentifier)
        
        if let downloadURL = downloadURL {
            Logger.verbose("Translations download url: \(downloadURL)")
            providers.append(TXDiskCacheProvider(fileURL: downloadURL))
        }
 
        return TXFileOutputCacheDecorator(
            fileURL: downloadURL,
            internalCache: TXReadonlyCacheDecorator(
                internalCache: TXProviderBasedCache(
                    providers: providers,
                    internalCache: TXStringUpdateFilterCache(
                        policy: updatePolicy,
                        internalCache: TXMemoryCache()
                    )
                )
            )
        )
    }
    
    /// Constructs the file URL of the translations file found in the main bundle of the app. The method
    /// can return nil if the file is not found.
    ///
    /// - Returns: The URL of the translations file in the main bundle of the app
    private static func bundleURL() -> URL? {
        let resourceComps = TXNative.STRINGS_FILENAME.split(separator: ".")
        
        guard resourceComps.count == 2 else {
            return nil
        }
        
        let resourceName = String(resourceComps[0])
        let resourceExtension = String(resourceComps[1])
        
        var bundle = Bundle.main
        
        // In case the SDK is executed by an app extension, the main bundle does
        // not return the main app bundle, but the extension one. In order to
        // retrieve the main app bundle, we would need to peel off two directory
        // levels - APP.app/PlugIns/APP_EXTENSION.appex
        //
        // Ref: https://stackoverflow.com/a/27849695/60949
        if bundle.bundleURL.pathExtension == "appex" {
            let mainAppBundleURL = bundle.bundleURL
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            if let mainAppBundle = Bundle(url: mainAppBundleURL) {
                bundle = mainAppBundle
            }
        }
        
        guard let url = bundle.url(forResource: resourceName,
                                   withExtension: resourceExtension) else {
            return nil
        }

        return url
    }
    
    private static let DOWNLOADED_FOLDER_NAME = "txnative"
    
    /// Constructs the file URL of the translations file found in the sandbox directory of the app that can be
    /// found either in the caches subdirectory of the sandbox directory of the main app, or in the app
    /// groups directory based on whether the `groupIdentifier` argument has been provided or not.
    ///
    /// The method expects to find the translations file on a separate directory
    /// (`DOWNLOADED_FOLDER_NAME`) but it doesn't look up whether the directory exists and doesn't
    /// create it.
    ///
    /// Pattern:
    /// `[caches or app group directory]/DOWNLOADED_FOLDER_NAME/STRINGS_FILENAME`
    ///
    /// - Parameters:
    ///   - groupIdentifier: The group identifier of the app group of the app (if available)
    /// - Returns: The URL of the translations file in the caches or the app group directory of the app.
    private static func downloadURL(groupIdentifier: String?) -> URL? {
        let fileManager = FileManager.default

        var baseURL: URL? = nil
        
        if let groupIdentifier = groupIdentifier,
           let groupURL = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            baseURL = groupURL
        }
        else {
            let cacheURLs = fileManager.urls(for: .cachesDirectory,
                                             in: .userDomainMask)
            
            if cacheURLs.count > 0 {
                baseURL = cacheURLs[0]
            }
        }
        
        guard let folderURL = baseURL?.appendingPathComponent(TXStandardCache.DOWNLOADED_FOLDER_NAME) else {
            return nil
        }
        
        return folderURL.appendingPathComponent(TXNative.STRINGS_FILENAME)
    }
}


/// A simple in-memory cache that updates its contents and returns the proper translation.
///
/// This class is not thread-safe, so be sure that you are calling the update / get methods from a serial queue.
public final class TXMemoryCache: NSObject {
    var translationsByLocale: TXTranslations = [:]
}

extension TXMemoryCache: TXCache {
    public func get() -> TXTranslations {
        return translationsByLocale
    }
    
    public func get(key: String, localeCode: String) -> String? {
        return translationsByLocale[localeCode]?[key]?[TXDecoratorCache.STRING_KEY]
    }
    
    public func update(translations: TXTranslations) {
        translationsByLocale = translations
    }
}

/// A no-op cache that doesn't support storing the values in-memory. Useful when the library needs to be
/// initialized without a cache (e.g. for the CLI tool).
public final class TXNoOpCache: NSObject, TXCache {
    public func get() -> TXTranslations {
        return [:]
    }
    
    public func get(key: String, localeCode: String) -> String? {
        return nil
    }
    
    public func update(translations: TXTranslations) {
        /// No-op
    }
}
