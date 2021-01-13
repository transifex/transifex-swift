//
//  Cache.swift
//  TransifexNative
//
//  Created by Dimitrios Bendilas on 17/7/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

public typealias TXStringInfo = [String: String]
public typealias TXLocaleStrings = [String: TXStringInfo]
public typealias TXTranslations = [String: TXLocaleStrings]

/// Overriding policy `TXStringOverrideFilterCache` decorator class so that any translations fed by
/// the `update()` method of the `TXCache` protocol are updated using one of the following policies.
@objc
public enum TXCacheOverridePolicy : Int {
    /// All of the cache entries are replaced with the new translations.
    case overrideAll
    /// All new translations are added to the cache, either updating existing translations or adding
    /// new ones.
    /// If a translation is not found in cache but exists in the new translations, it's not added.
    /// If a translation is found in cache but doesn't exist in the new translations, it's left untouched.
    /// Empty cache entries from the new translations are filtered out.
    case overrideUsingTranslatedOnly
    /// Only the translations not existing in the cache are updated.
    /// If a translation is found in the cache but not in the new translations, it's left untouched.
    /// Empty cache entries from the new translations are filtered out.
    case overrideUntranslatedOnly
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
@objc
public class TXDiskCacheProvider: NSObject, TXCacheProvider {
    /// The translations extracted from disk after initialization.
    public let translations: TXTranslations?
    
    @objc
    public init(fileURL: URL) {
        self.translations = TXDiskCacheProvider.load(from: fileURL)
    }
    
    /// Loads the translations from a file url, returns nil in case of an error
    /// - Parameter fileURL: The url of the file that contains the translations
    /// - Returns: The translations or nil if there was an error
    private static func load(from fileURL: URL) -> TXTranslations? {
        var fileData: Data?
    
        do {
            fileData = try Data(contentsOf: fileURL)
        }
        catch {
            print("\(#function) fileURL: \(fileURL) Data error: \(error)")
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
            print("\(#function) fileURL: \(fileURL) Decode Error: \(error)")
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
@objc
public class TXDecoratorCache: NSObject, TXCache {
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
@objc
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
                print("\(#function) Error: \(error)")
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
@objc
public final class TXReadonlyCacheDecorator: TXDecoratorCache {
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
@objc
public final class TXProviderBasedCache: TXDecoratorCache {
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

/// Class responsible for updating the passed internalCache using a certain override policy defined
/// in the `TXCacheOverridePolicy` enum. This is done by filtering any translations that are passed
/// via the `update(translations:)` call using an override policy that checks both the passed
/// translations and the internal cache state to decide whether a translation should update the internal cache
/// or not.
@objc
public final class TXStringOverrideFilterCache: TXDecoratorCache {
    let policy: TXCacheOverridePolicy
    
    @objc
    public init(policy: TXCacheOverridePolicy,
                internalCache: TXCache) {
        self.policy = policy
        super.init(internalCache: internalCache)
    }
    
    override public func update(translations: TXTranslations) {
        if policy == .overrideAll {
            super.update(translations: translations)
            return
        }
        
        var updatedTranslations = self.get()
    
        for (localeCode, localeTranslations) in translations {
            for (stringKey, translation) in localeTranslations {
                // Make sure that the new translation has a value and it's not
                // an empty string.
                guard let translatedString = translation[TXDecoratorCache.STRING_KEY],
                      translatedString.count > 0 else {
                    continue
                }
                
                    // If the policy is set to override untranslated only, then
                    // update the cache only if there's no existing translation
                    // for that stringKey.
                if (policy == .overrideUntranslatedOnly
                    && self.get(key: stringKey,
                                localeCode: localeCode) == nil)
                   ||
                    // If the policy is set to override using translated only,
                    // then always update the cache.
                    policy == .overrideUsingTranslatedOnly {
                    if updatedTranslations[localeCode] == nil {
                        updatedTranslations[localeCode] = [:]
                    }

                    updatedTranslations[localeCode]?[stringKey] = translation
                }
            }
        }

        super.update(translations: updatedTranslations)
    }
}

/// The standard cache that the TxNative SDK is initialized with, if no other cache is provided.
///
/// The cache gets initialized using the decorators implemented in the Caches.swift file of the SDK so that it
/// reads from any existing translation files either from the app bundle or the app sandbox. The cache is also
/// responsible for creating or updating the sandbox file with new translations when they will become available
/// and it offers  a memory cache for retrieving such translations so that they can be displayed in the UI.
@objc
public final class TXStandardCache: TXDecoratorCache {
    /// Initializes the cache using a specific override policy and an optional group identifier based on the
    /// architecture of the application using the SDK.
    ///
    /// - Parameters:
    ///   - overridePolicy: The specific override policy to be used when updating the internal
    ///   memory cache with the stored contents from disk. Defaults to .overrideAll.
    ///   - groupIdentifier: The group identifier of the app, if the app makes use of the app groups
    /// entitlement. Defaults to nil.
    @objc
    public init(overridePolicy: TXCacheOverridePolicy = .overrideAll,
                groupIdentifier: String? = nil) {
        var providers: [TXCacheProvider] = []
        
        if let bundledURL = TXStandardCache.bundleURL() {
            providers.append(TXDiskCacheProvider(fileURL: bundledURL))
        }
        
        let downloadURL = TXStandardCache.downloadURL(groupIdentifier: groupIdentifier)
        
        if let downloadURL = downloadURL {
            providers.append(TXDiskCacheProvider(fileURL: downloadURL))
        }
 
        let cache = TXFileOutputCacheDecorator(
            fileURL: downloadURL,
            internalCache: TXReadonlyCacheDecorator(
                internalCache: TXProviderBasedCache(
                    providers: providers,
                    internalCache: TXStringOverrideFilterCache(
                        policy: overridePolicy,
                        internalCache: TXMemoryCache()
                    )
                )
            )
        )
        
        super.init(internalCache: cache)
    }
    
    /// Constructs the file URL of the translations file found in the main bundle of the app. The method
    /// can return nil if the file is not found.
    ///
    /// - Returns: The URL of the translations file in the main bundle of the app
    private static func bundleURL() -> URL? {
        let resourceComps = TxNative.STRINGS_FILENAME.split(separator: ".")
        
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
        
        return folderURL.appendingPathComponent(TxNative.STRINGS_FILENAME)
    }
}


/// A simple in-memory cache that updates its contents and returns the proper translation.
///
/// This class is not thread-safe, so be sure that you are calling the update / get methods from a serial queue.
@objc
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
@objc
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
