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
    
    /// Update the cache entry of a given locale code with a dictionary of translations that is structured
    /// like this:
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
    ///     'gr' : {},
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - localeCode: The locale code that is going to be updated
    ///   - translations: The updated dictionary structure of translations
    func update(localeCode: String, translations: LocaleStrings)
    
}

/// A cache that holds translations in memory
public final class MemoryCache : NSObject {
    
    var translationsByLocale: [String: LocaleStrings]
    
    @objc
    public override init() {
        self.translationsByLocale = [:]
    }
}

extension MemoryCache : Cache {
    public func get(key: String, localeCode: String) -> String? {
        return translationsByLocale[localeCode]?[key]?["string"]
    }
    
    public func update(localeCode: String, translations: LocaleStrings) {
        translationsByLocale[localeCode] = translations
    }
}
