//
//  cache.swift
//  toolkit
//
//  Created by Dimitrios Bendilas on 17/7/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

public typealias StringInfo = [String: String]
public typealias LocaleStrings = [String: StringInfo]

/**
 A protocol for classes that act as cache of translations
 */
public protocol Cache {
    
    /**
     Replace the cache with the given data.

     where `data` is expected to be structured like:
     {
         'fr': {
             'key1':  {'string': '...'},
             'key2': {'string': '...'},
         }),
         'de': (True, {
             'key3': {'string': '...'},
         }),
         'gr': {},
     }
     */
    func get(key: String, localeCode: String) -> String?
    
    func update(localeCode: String, translations: LocaleStrings)
    
}

/**
 A cache that holds translations in memory.
 */
public class MemoryCache : Cache {
    
    var translationsByLocale: [String: LocaleStrings]
    
    public init() {
        translationsByLocale = [:]
    }
    
    public func get(key: String, localeCode: String) -> String? {
        return translationsByLocale[localeCode]?[key]?["string"]
    }
    
    public func update(localeCode: String, translations: LocaleStrings) {
        translationsByLocale[localeCode] = translations
    }
}
