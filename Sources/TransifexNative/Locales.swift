//
//  locales.swift
//  toolkit
//
//  Created by Dimitrios Bendilas on 19/7/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

/// Keeps track of the locale-related information for the application,
/// such as supported locales, source and current locale.
public final class LocaleState {
    
    /// The locale of the source language
    private var _sourceLocale: String = "en"
    
    /// The currently selected locale that is being displayed in the app
    private var _currentLocale: String = "en"
    
    /// A list of all locales supported in the app
    private var _appLocales: [String] = ["en"]
    
    /**
     Constructor.
     
     - sourceLocale: the locale of the source language, defaults to "en"
     - appLocales: a list of all locales supported by the application, defaults to ["en"]
     - currentLocale: the currently active locale in the app, defaults to "en"
     */
    public init(sourceLocale: String? = nil, appLocales: [String] = [], currentLocale: String? = nil) {
        if sourceLocale != nil {
            _sourceLocale = sourceLocale!
        }
        if currentLocale != nil {
            _currentLocale = currentLocale!
        }
        self.appLocales = appLocales
    }
    
    /// The locale of the source language
    public var sourceLocale: String {
        set { _sourceLocale = newValue }
        get { _sourceLocale }
    }
    
    /// The currently selected locale
    public var currentLocale: String {
        set { _currentLocale = newValue }
        get { _currentLocale }
    }
    
    // A list of all locales supported in the app
    public var appLocales: [String] {
        set {
            _appLocales = newValue
            if _appLocales.firstIndex(of: _currentLocale) == nil {
                _appLocales.insert(_currentLocale, at: 0)
            }
        }
        get { _appLocales }
    }
    
    /**
     Returns true if the given locale is the source locale, false otherwise.
     
     - locale: the locale to check against
     */
    public func isSource(_ locale: String) -> Bool {
        return locale == sourceLocale
    }
    
    /**
     Returns true if the given locale is the currently selected locale, false otherwise.
     
     - locale: the locale to check against
     */
    public func isCurrent(_ locale: String) -> Bool {
        return locale == currentLocale
    }
    
    /**
     Returns true if the given locale is defined in the app configuration, false otherwise.
     
     - locale: the locale to check against
     */
    public func isAvailableInApp(_ locale: String) -> Bool {
        return appLocales.firstIndex(of: locale) != nil
    }
    
}
