//
//  Cache.swift
//  TransifexNative
//
//  Created by Dimitrios Bendilas on 17/7/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

public typealias StringInfo = [String: String]
public typealias LocaleStrings = [String: StringInfo]

/// A protocol for classes that act as cache for translations
@objc
public protocol Cache {
    
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
    func update(translations: [String: LocaleStrings])
}

/// A cache that holds translations in memory
public final class MemoryCache : NSObject {
    
    /// Serial dispatch queue that ensures that cache will only be updated / read by one thread
    let cacheQueue = DispatchQueue(label: "com.transifex.native.memorycache")
    
    var translationsByLocale: [String: LocaleStrings]
    
    @objc
    public override init() {
        self.translationsByLocale = [:]
    }
}

extension MemoryCache : Cache {
    public func update(translations: [String: LocaleStrings]) {
        cacheQueue.sync {
            for (localeCode, localeTranslations) in translations {
                translationsByLocale[localeCode] = localeTranslations
            }
        }
    }
    
    public func get(key: String, localeCode: String) -> String? {
        cacheQueue.sync {
            return translationsByLocale[localeCode]?[key]?["string"]
        }
    }
}
