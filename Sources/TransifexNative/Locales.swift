//
//  Locales.swift
//  TransifexNative
//
//  Created by Dimitrios Bendilas on 19/7/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

/// Protocol that developers can use to create custom classes that return the current locale of the app.
/// If no CurrentLocaleProvider is provided in LocaleState constructor, the UserDefaultsLocaleProvider
/// is used.
@objc
public protocol CurrentLocaleProvider {

    func currentLocale() -> String
}

/// Class that returns the current locale found in the User Defaults dictionary of the app
public final class UserDefaultsLocaleProvider : NSObject, CurrentLocaleProvider {
    
    private static let APPLE_LANGUAGE_KEY = "AppleLanguages"
    private static let FALLBACK_LANGUAGE = "en"
    
    public func currentLocale() -> String {
        let userDefaults = UserDefaults.standard
        
        guard let langArray = userDefaults.object(forKey: UserDefaultsLocaleProvider.APPLE_LANGUAGE_KEY) as? NSArray,
              let current = langArray.firstObject as? String else {
            print("Error: Language code couldn't be found, falling back to \(UserDefaultsLocaleProvider.FALLBACK_LANGUAGE).")
            return UserDefaultsLocaleProvider.FALLBACK_LANGUAGE
        }
        
        return current
    }
}

/// Keeps track of the locale-related information for the application,
/// such as supported locales, source and current locale.
public final class LocaleState : NSObject {
    
    /// The locale of the source language
    @objc
    public private(set) var sourceLocale: String
    
    /// The currently selected locale that is being displayed in the app
    @objc
    public var currentLocale : String {
        get {
            return currentLocaleProvider.currentLocale()
        }
    }
    
    /// A list of all locales supported in the app
    @objc
    public private(set) var appLocales : [String]
    
    /// The provider object that provides the current locale value
    /// whenever it is requested by the currentLocale property.
    private var currentLocaleProvider : CurrentLocaleProvider
    
    /// Constructor.
    ///
    /// - Parameters:
    ///   - sourceLocale: the locale of the source language, defaults to "en"
    ///   - appLocales: a list of all locales supported by the application, defaults to ["en"]
    ///   - currentLocaleProvider: an object conforming to CurrentLocaleProvider protocol,
    /// defaults to UserDefaultsLocaleProvider
    @objc
    public init(sourceLocale: String? = nil,
         appLocales: [String] = [],
         currentLocaleProvider: CurrentLocaleProvider? = nil
    ) {
        self.sourceLocale = sourceLocale ?? "en"
        if appLocales.count == 0 {
            self.appLocales = [ self.sourceLocale ]
        }
        else {
            // Make sure we filter all duplicate values
            // by converting the array to a Set and back
            // to an array.
            self.appLocales = Array(Set(appLocales))
        }
        self.currentLocaleProvider = currentLocaleProvider ?? UserDefaultsLocaleProvider()
    }
    
    /// Returns true if the given locale is the source locale, false otherwise.
    ///
    /// - Parameter locale: the locale to check against
    /// - Returns: true if the given locale is the source locale, false otherwise
    public func isSource(_ locale: String) -> Bool {
        return locale == sourceLocale
    }
    
    /// Returns true if the given locale is the currently selected locale, false otherwise.
    ///
    /// - Parameter locale: the locale to check against
    /// - Returns: true if the given locale is the currently selected locale, false otherwise
    public func isCurrent(_ locale: String) -> Bool {
        return locale == currentLocale
    }
    
    /// Returns true if the given locale is defined in the app configuration, false otherwise.
    ///
    /// - Parameter locale: the locale to check against
    /// - Returns: true if the given locale is defined in the app configuration, false otherwise
    public func isAvailableInApp(_ locale: String) -> Bool {
        return appLocales.contains(locale)
    }
}
