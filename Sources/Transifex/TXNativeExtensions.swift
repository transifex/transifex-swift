//
//  TXNativeExtensions.swift
//  Transifex
//
//  Created by Stelios Petrakis on 16/11/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

// Note:
// Please copy this file to your project and add it to all of the app's targets
// if you are making use of the following Swift methods:
//
// * NSString.localizedStringWithFormat(_ format:, _ args:)
// * String.localizedStringWithFormat(_ format:, _ arguments:)
//
// For the String.init(localized:...) initializers below, please consult the
// 'Limitations' section of README.md before un-commenting that section of the
// code:
// * String.init(localized:)
// * String.init(localized:options:)
// * String.init(localized:defaultValue:table:bundle:locale:comment:)
// * String.init(localized:defaultValue:options:table:bundle:locale:comment:)
// * String.init(localized:table:bundle:locale:comment:)
// * String.init(localized:options:table:bundle:locale:comment:)
//
// If your code makes use of the Objective-C's
// [NSString localizedStringWithFormat:...] method, you don't need to copy this
// file.

import Foundation
import Transifex

/// Override Swift String.localizedStringWithFormat: method
public extension String {
    static func localizedStringWithFormat(
        _ format: String, _ arguments: CVarArg...
    ) -> String {
        guard let localized = TXNative.localizedString(format: format,
                                                       arguments: arguments) else {
            return String(format: format, locale: Locale.current,
                          arguments: arguments)
        }
        
        return localized
    }
}

/// Override Swift NSString.localizedStringWithFormat: method
public extension NSString {
    class func localizedStringWithFormat(
        _ format: NSString, _ args: CVarArg...
    ) -> Self {
        guard let localized = TXNative.localizedString(format: format as String,
                                                       arguments: args) as? Self else {
            return withVaList(args) {
                self.init(format: format as String, locale: Locale.current,
                          arguments: $0)
            }
        }
        
        return localized
    }
}
/**
/// Replace String(localized:) initializers.
///
/// Please consult the 'Limitations' section of README.md for more information.
public extension String {
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    init(localized key: StaticString, defaultValue: String.LocalizationValue,
         table: String? = nil, bundle: Bundle? = nil, locale: Locale = .current,
         comment: StaticString? = nil) {
        self = TXNative.translate(staticString: key, defaultValue: defaultValue,
                                  table: table, bundle: bundle, locale: locale,
                                  extractionType: .reflection)
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    init(localized keyAndValue: String.LocalizationValue, table: String? = nil,
         bundle: Bundle? = nil, locale: Locale = .current,
         comment: StaticString? = nil) {
        self = TXNative.translate(localizationValue: keyAndValue, table: table,
                                  bundle: bundle, locale: locale,
                                  extractionType: .reflection)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    init(localized resource: LocalizedStringResource) {
        self = TXNative.translate(resource: resource,
                                  extractionType: .reflection)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    init(localized resource: LocalizedStringResource,
         options: String.LocalizationOptions) {
        self = TXNative.translate(resource: resource, options: options,
                                  extractionType: .reflection)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    init(localized key: StaticString, defaultValue: String.LocalizationValue,
         options: String.LocalizationOptions, table: String? = nil,
         bundle: Bundle? = nil, locale: Locale = .current,
         comment: StaticString? = nil) {
        self = TXNative.translate(staticString: key, defaultValue: defaultValue,
                                  options: options, table: table,
                                  bundle: bundle, locale: locale,
                                  extractionType: .reflection)
    }

    @available(macOS 13, iOS 16, tvOS 16, watchOS 9, *)
    init(localized keyAndValue: String.LocalizationValue,
         options: String.LocalizationOptions, table: String? = nil,
         bundle: Bundle? = nil, locale: Locale = .current,
         comment: StaticString? = nil) {
        self = TXNative.translate(localizationValue: keyAndValue,
                                  options: options, table: table,
                                  bundle: bundle, locale: locale,
                                  extractionType: .reflection)
    }
}
**/
