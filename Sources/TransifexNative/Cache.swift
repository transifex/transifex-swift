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

/// A protocol for classes that act as cache for translations.
@objc
public protocol TXCache {
    
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
    ///   - replaceEntries: whether the passed translations should replace all of the existing
    ///   entries or leave the entries not included in the translations argument untouched.
    func update(translations: TXTranslations,
                replaceEntries: Bool)
}

/// A protocol for classes that act as providers of cached translations (e.g. extracting them from a file)
@objc
public protocol TXCacheProvider {
    /// Returns the translations from the current cache provider.
    func getTranslations() -> TXTranslations?
}

/// Cache provider that loads translations from disk
@objc
public final class TXDiskCacheProvider: NSObject, TXCacheProvider {
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

/// Composite class that accepts a number of cache providers, an internal cache and whether the providers
/// should replace the entries of the cache or not. The providers are then used to update the internal class
/// in the order they are added in the providers list.
@objc
public final class TXProviderBasedCache: NSObject {
    let memoryCache: TXCache
    
    @objc
    public init(providers: [TXCacheProvider],
                memoryCache: TXCache,
                replaceEntries: Bool = false) {
        self.memoryCache = memoryCache
        for provider in providers {
            if let providerTranslations = provider.getTranslations() {
                self.memoryCache.update(translations: providerTranslations,
                                        replaceEntries: replaceEntries)
            }
        }
        super.init()
    }
}

extension TXProviderBasedCache: TXCache {
    public func get(key: String, localeCode: String) -> String? {
        return memoryCache.get(key: key, localeCode: localeCode)
    }
    
    /// Provider based cache doesn't update its internal cache after being initialiazed, so the update
    /// method of the TXCache protocol is a no-op.
    
    public func update(translations: TXTranslations,
                       replaceEntries: Bool) {
        /// No-op
    }
}

@objc
public final class TXDefaultCache: NSObject {
    private static let DOWNLOADED_FOLDER_NAME = "txnative"
    
    /// Dispatch queue that ensures that the downloaded strings are written to a file in a serial fashion.
    let cacheQueue = DispatchQueue(label: "com.transifex.native.memorycache")
    
    private let internalCache: TXCache
    private let groupIdentifier: String?
    
    @objc
    public init(groupIdentifier: String? = nil,
                replaceEntries: Bool = false) {
        var providers: [TXCacheProvider] = []
        
        if let bundledURL = TXDefaultCache.bundledTranslationsURL() {
            providers.append(TXDiskCacheProvider(fileURL: bundledURL))
        }
        
        if let downloadedURL = TXDefaultCache.downloadedTranslationsURL(groupIdentifier: groupIdentifier) {
            providers.append(TXDiskCacheProvider(fileURL: downloadedURL))
        }
    
        self.groupIdentifier = groupIdentifier
        self.internalCache = TXProviderBasedCache(providers: providers,
                                                  memoryCache: TXMemoryCache(),
                                                  replaceEntries: replaceEntries)
    }
    
    /// - Returns: The URL of the translations file in the main bundle of the app
    private static func bundledTranslationsURL() -> URL? {
        let resourceComps = TxNative.STRINGS_FILENAME.split(separator: ".")
        
        guard resourceComps.count == 2 else {
            return nil
        }
        
        let resourceName = String(resourceComps[0])
        let resourceExtension = String(resourceComps[1])
        
        guard let url = Bundle.main.url(forResource: resourceName,
                                        withExtension: resourceExtension) else {
            return nil
        }

        return url
    }
    
    /// - Parameters:
    ///   - groupIdentifier: The group identifier of the app group of the app (if available)
    ///   - includeFilename: Whether the final url will include the translations filename or just its folder
    /// - Returns: The URL of the translations file (or its folder if includeFilename=false) in the caches
    /// or the app group directory of the app.
    ///
    /// Pattern:
    /// `[caches or app group directory]/DOWNLOADED_FOLDER_NAME/{STRINGS_FILENAME}`
    private static func downloadedTranslationsURL(groupIdentifier: String?,
                                                  includeFilename: Bool = true) -> URL? {
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
        
        guard let folderURL = baseURL?.appendingPathComponent(TXDefaultCache.DOWNLOADED_FOLDER_NAME) else {
            return nil
        }
        
        if !includeFilename {
            return folderURL
        }
        
        return folderURL.appendingPathComponent(TxNative.STRINGS_FILENAME)
    }
    
    enum StoringErrors: Error {
        case urlNotFound
        case encodingFailed
    }
    
    /// Serializes passed translations and stores them in the `TxNative.STRINGS_FILENAME` file
    /// in the caches directory of the app.
    ///
    /// - Parameter translations: The passed translations
    /// - Throws: The error that may occur during serialization, directory creation or file writing.
    private func storeTranslations(translations: TXTranslations) throws {
        guard let folderURL = TXDefaultCache.downloadedTranslationsURL(groupIdentifier: groupIdentifier,
                                                                       includeFilename: false) else {
            throw StoringErrors.urlNotFound
        }
        
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
        
        let outputFileURL = folderURL.appendingPathComponent(TxNative.STRINGS_FILENAME)
        
        do {
            try serializedTranslations.write(to: outputFileURL,
                                             atomically: true,
                                             encoding: .utf8)
        }
    }
}

extension TXDefaultCache: TXCache {
    public func get(key: String, localeCode: String) -> String? {
        /// The get() method here will call TXProviderBasedCache.get() which in turn is going to call
        /// TXMemoryCache.get().
        return internalCache.get(key: key, localeCode: localeCode)
    }
    
    public func update(translations: TXTranslations,
                       replaceEntries: Bool) {
        /// When update is called in the default cache, we ignore the replaceEntries flag as we always
        /// want to store the passed translations in a file in the downloaded translations url.
        cacheQueue.async {
            do {
                try self.storeTranslations(translations: translations)
            }
            catch {
                print("\(#function) Error: \(error)")
            }
        }
    }
}


/// A simple in-memory cache that updates its contents and returns the proper translation.
///
/// This class is not thread-safe, so be sure that you are calling the update / get methods from a serial queue.
@objc
public final class TXMemoryCache: NSObject {
    private static let STRING_KEY = "string"
    
    var translationsByLocale: TXTranslations = [:]
}

extension TXMemoryCache: TXCache {
    public func get(key: String, localeCode: String) -> String? {
        return translationsByLocale[localeCode]?[key]?[TXMemoryCache.STRING_KEY]
    }
    
    public func update(translations: TXTranslations,
                       replaceEntries: Bool) {
        /// If the replaceEntries is true, we replace the whole cache with the translations of the provided
        /// provider.
        if replaceEntries {
            translationsByLocale = translations
        }
        else {
            /// Otherwise we check whether each key in each locale of the provider exists in cache and
            /// we update it, while leaving the rest of the keys and locales untouched.
            for (localeCode, localeTranslations) in translations {
                if translationsByLocale[localeCode] != nil {
                    for (stringKey, translation) in localeTranslations {
                        translationsByLocale[localeCode]?[stringKey] = translation
                    }
                } else {
                    translationsByLocale[localeCode] = localeTranslations
                }
            }
        }
    }
}

/// A no-op cache that doesn't support storing the values in-memory. Useful when the library needs to be
/// initialized without a cache (e.g. for the CLI tool).
@objc
public final class TXNoOpCache: NSObject, TXCache {
    public func get(key: String, localeCode: String) -> String? {
        return nil
    }
    
    public func update(translations: TXTranslations,
                       replaceEntries: Bool) {
        /// No-op
    }
}
