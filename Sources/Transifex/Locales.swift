//
//  Locales.swift
//  Transifex
//
//  Created by Dimitrios Bendilas on 19/7/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

/// Protocol that developers can use to create custom classes that return the current locale of the app.
/// If no CurrentLocaleProvider is provided in TXLocaleState constructor, the TXPreferredLocaleProvider
/// is used.
@objc
public protocol TXCurrentLocaleProvider {
    /// Return the current locale to be used by the SDK
    func currentLocale() -> String
}

/// Class that returns the language code of the current user's locale and falls back to "en" if the language
/// code cannot be found.
public final class TXPreferredLocaleProvider : NSObject {
    private var _currentLocale : String
    
    override init() {
        // Fetch the current locale on initialization and return it when it's
        // requested by the `currentLocale()` method.
        _currentLocale = TXPreferredLocaleProvider.getCurrentLocale()

        super.init()

        // Detect whenever the current locale is changed and update that value.
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(currentLocaleDidChange),
                                               name: NSLocale.currentLocaleDidChangeNotification,
                                               object: nil)
    }
    
    @objc
    private func currentLocaleDidChange() {
        _currentLocale = TXPreferredLocaleProvider.getCurrentLocale()
    }
    
    private static func getPreferredLocale() -> Locale {
        guard let preferredIdentifier = Locale.preferredLanguages.first else {
            return Locale.autoupdatingCurrent
        }
        return Locale(identifier: preferredIdentifier)
    }

    private static func getCurrentLocale() -> String {
        return getPreferredLocale().languageCode ?? "en"
    }
}

extension TXPreferredLocaleProvider : TXCurrentLocaleProvider {
    /// The current user's locale.
    ///
    /// - Returns: The current user's locale
    public func currentLocale() -> String {
        return _currentLocale
    }
}

/// Keeps track of the locale-related information for the application,
/// such as supported locales, source and current locale.
public final class TXLocaleState : NSObject {
    
    /// The locale of the source language
    @objc
    public private(set) var sourceLocale: String
    
    /// The currently selected locale that is being displayed in the app
    @objc
    public var currentLocale: String {
        get {
            return currentLocaleProvider.currentLocale()
        }
    }
    
    /// A list of all locales supported in the app, including the source locale.
    @objc
    public private(set) var appLocales: [String]
    
    /// An array containing the app's locales without the source locale.
    @objc
    public private(set) var translatedLocales: [String]
    
    /// The provider object that provides the current locale value
    /// whenever it is requested by the currentLocale property.
    private var currentLocaleProvider: TXCurrentLocaleProvider
    
    private static let DEFAULT_SOURCE_LOCALE = "en"
    
    /// Constructor.
    ///
    /// - Parameters:
    ///   - sourceLocale: the locale of the source language, defaults to "en" if no source locale is
    ///   provided
    ///   - appLocales: a list of all locales supported by the application, defaults to the source locale
    ///   if the appLocales list is empty. If the source locale is not included in this list, it's added during
    ///   initialization.
    ///   - currentLocaleProvider: an object conforming to CurrentLocaleProvider protocol,
    /// defaults to TXPreferredLocaleProvider
    @objc
    public init(sourceLocale: String? = nil,
         appLocales: [String] = [],
         currentLocaleProvider: TXCurrentLocaleProvider? = nil
    ) {
        let sourceLocale = sourceLocale ?? TXLocaleState.DEFAULT_SOURCE_LOCALE
        self.sourceLocale = sourceLocale
        
        // Make sure we filter all duplicate values
        // by converting the array to a Set.
        var distinctAppLocales = Set(appLocales)
        // Insert the source locale in case it hasn't been added.
        distinctAppLocales.insert(sourceLocale)
        self.appLocales = Array(distinctAppLocales)
        
        self.translatedLocales = self.appLocales.filter { $0 != sourceLocale }
        
        self.currentLocaleProvider = currentLocaleProvider ?? TXPreferredLocaleProvider()
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
    
    /// Description of the source string used for debugging purposes
    public override var debugDescription: String {
        """
TXLocaleState(sourceLocale: \(sourceLocale), appLocales: \(appLocales))
"""
    }
}
