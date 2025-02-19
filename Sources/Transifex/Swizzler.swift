//
//  Swizzler.swift
//  Transifex
//
//  Created by Stelios Petrakis on 5/11/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation
import TransifexObjCRuntime

/// Swizzles all localizedString() calls made either by Storyboard files or by the use of NSLocalizedString()
/// function in code.
class SwizzledBundle : Bundle, @unchecked Sendable {
    // NOTE:
    // We can't override the `localizedAttributedString(forKey:value:table:)`
    // method here, as it's not exposed in Swift.
    // We can neither use swizzling in Swift for the same reason.
    // In order to intercept this method (that SwiftUI uses for all its text
    // components), we rely on the `TXNativeObjecSwizzler` to swizzle that
    // method that is also going to work on runtime for Swift/SwiftUI.
    override func localizedString(forKey key: String,
                                  value: String?,
                                  table tableName: String?) -> String {
        // Apply the swizzled method only if:
        // * Swizzler has been activated.
        // * Swizzling was not disabled temporarily using the
        //   `SKIP_SWIZZLING_VALUE` flag.
        // * The key does not match the reserved Transifex StringsDict key that
        //   is used to extract the proper pluralization rule.
        //   NOTE: While running the Unit Test suite of the Transifex SDK, we
        //   noticed that certain unit tests (e.g. `testPlatformFormat`,
        //   `testPlatformFormatMultiple`) were triggering the Transifex module
        //   bundle to load to due to the call of the `extractPluralizationRule`
        //   method. Even though the loading of the module bundling was
        //   happening after the Swizzler was activated, subsequent unit tests
        //   had the bundle already loaded in the `Bundle.allBundles` array,
        //   causing the bundle to also be swizzled, thus preventing the
        //   `Localizable.stringsdict` to report the correct pluralization rule.
        if Swizzler.activated
            && value != Swizzler.SKIP_SWIZZLING_VALUE
            && key != PlatformFormat.TRANSIFEX_STRINGSDICT_KEY {
            return Swizzler.localizedString(forKey: key,
                                            value: value,
                                            table: tableName)
        }
        else {
            return super.localizedString(forKey: key,
                                         value: value,
                                         table: tableName)
        }
    }
}

/// Handles all Swizzling logic so that existing calls to localized methods are intercepted by the
/// Transifex library.
class Swizzler {
    
    internal static let SKIP_SWIZZLING_VALUE = "__TX_SKIP_SWIZZLING__"
    
    internal static let PARAM_VALUE_KEY = "_value"
    internal static let PARAM_TABLE_KEY = "_table"
    internal static let PARAM_ARGUMENTS_KEY = "_arguments"
    
    /// String to be returned when no translation provider is provided
    private static let MISSING_PROVIDER = "MISSING TRANSLATION PROVIDER"
    
    /// True if Swizzler is activated, False otherwise
    internal private(set) static var activated = false
    
    /// The translation provider that will receive the arguments of the Swizzled methods, generate the
    /// final string and return it.
    private static var translationProvider : TranslationProvider?
    
    /// Activates the Swizzler
    internal static func activate(translationProvider : TranslationProvider) {
        guard activated == false else {
            return
        }
        
        self.translationProvider = translationProvider

        // Swizzle `NSBundle.localizedString(String,String?,String?)` method
        // for Swift.
        activate(bundles: Bundle.allBundles)

        // Swizzle `-[NSString localizedStringWithFormat:]` method for
        // Objective-C.
        TXNativeObjcSwizzler.swizzleLocalizedString {
            return self.localizedString(format: $0,
                                        arguments: $1)
        }

        // Swizzle `-[NSBundle localizedAttributedStringForKey:value:table:]`
        // method for Objective-C, Swift and SwiftUI.
        TXNativeObjcSwizzler.swizzleLocalizedAttributedString(self,
                                                              selector: swizzledLocalizedAttributedStringSelector())
        
        activated = true
    }

    /// Deactivates Swizzler
    internal static func deactivate() {
        guard activated else {
            return
        }

        // Deactivate swizzled bundles
        deactivate(bundles: Bundle.allBundles)

        // Deactivate swizzling in:
        // * `-[NSString localizedStringWithFormat:]`
        // * `-[NSBundle localizedAttributedStringForKey:value:table:]`
        TXNativeObjcSwizzler.revertLocalizedString()
        TXNativeObjcSwizzler.revertLocalizedAttributedString(self,
                                                             selector: swizzledLocalizedAttributedStringSelector())

        translationProvider = nil

        activated = false
    }

    private static func swizzledLocalizedAttributedStringSelector() -> Selector {
        return #selector(swizzledLocalizedAttributedString(forKey:value:table:))
    }

    @objc
    private func swizzledLocalizedAttributedString(forKey key: String,
                                                   value: String?,
                                                   table tableName: String?) -> NSAttributedString {
        let swizzledString = Swizzler.localizedString(forKey: key,
                                                      value: value,
                                                      table: tableName)
        // On supported platforms, attempt to decode the attributed string as
        // markdown in case it contains style decorators (e.g. *italic*,
        // **bold** etc).
#if os(iOS)
        if #available(iOS 15, *) {
            return Self.attributedString(with: swizzledString)
        }
#elseif os(watchOS)
        if #available(watchOS 8, *) {
            return Self.attributedString(with: swizzledString)
        }
#elseif os(tvOS)
        if #available(tvOS 15, *) {
            return Self.attributedString(with: swizzledString)
        }
#elseif os(macOS)
        if #available(macOS 12, *) {
            return Self.attributedString(with: swizzledString)
        }
#endif
        // Otherwise, return a simple attributed string
        return NSAttributedString(string: swizzledString)
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    private static func attributedString(with swizzledString: String) -> NSAttributedString {
        var string: AttributedString
        do {
            string = try AttributedString(markdown: swizzledString)
        }
        catch {
            // Fallback to the non-Markdown version in case of an error
            // during Markdown parsing.
            return NSAttributedString(string: swizzledString)
        }
        // If successful, return the Markdown-styled string
        return NSAttributedString(string)
    }

    /// Swizzles the passed bundles so that their localization methods are intercepted.
    ///
    /// - Parameter bundles: The bundles to be swizzled
    internal static func activate(bundles: [Bundle]) {
        bundles.forEach({ (bundle) in
            guard !bundle.isKind(of: SwizzledBundle.self) else {
                return
            }
            object_setClass(bundle, SwizzledBundle.self)
        })
    }
    
    /// Reverts the class of the passed swizzled bundles to original `Bundle` class.
    ///
    /// - Parameter bundles: The bundles to be reverted.
    internal static func deactivate(bundles: [Bundle]) {
        bundles.forEach({ (bundle) in
            guard bundle.isKind(of: SwizzledBundle.self) else {
                return
            }
            object_setClass(bundle, Bundle.self)
        })
    }

    /// Centralized method that all swizzled or overriden localizedStringWithFormat: methods will call once
    /// Swizzler is activated.
    ///
    /// - Parameters:
    ///   - format: The format string
    ///   - arguments: An array of arguments of arbitrary type
    /// - Returns: The final string
    internal static func localizedString(format: String,
                                         arguments: [Any]) -> String {
        guard let translationProvider = translationProvider else {
            return MISSING_PROVIDER
        }
    
        var params : [String : Any] = [:]

        if arguments.count > 0 {
            params[PARAM_ARGUMENTS_KEY] = arguments
        }
        
        return translationProvider.translate(sourceString: format,
                                             params: params)
    }
    
    /// Centralized method that all localizedString() / NSLocalizedString() methods will call once Swizzler is
    /// activated.
    ///
    /// - Parameters:
    ///   - key: The key for a string in the table identified by tableName.
    ///   - value: The value to return if key is nil or if a localized string for key can’t be found in the table.
    ///   - tableName: The receiver’s string table to search. If tableName is nil or is an empty string,
    ///   the method attempts to use the table in Localizable.strings.
    /// - Returns: The final string
    fileprivate static func localizedString(forKey key: String,
                                            value: String?,
                                            table tableName: String?) -> String {
        guard let translationProvider = translationProvider else {
            return MISSING_PROVIDER
        }
        
        var params : [String : Any] = [:]
        
        // When NSLocalizedString() is called in code, the sourceString is used
        // as the PARAM_VALUE_KEY contains an empty string, so we don't include
        // it in the params dictionary for simplification.
        if let value = value,
           value.count > 0 {
            params[PARAM_VALUE_KEY] = value
        }
        
        if let tableName = tableName,
           tableName.count > 0 {
            params[PARAM_TABLE_KEY] = tableName
        }
        
        return translationProvider.translate(sourceString: key,
                                             params: params)
    }
    
    /// Method called by the TXNativeObjcSwizzler that contains the arguments of the NSString
    /// localizedStringWithFormat: method and the format string.
    ///
    /// - Parameters:
    ///   - format: The format string
    ///   - arguments: The array of the extracted arguments
    /// - Returns: The final string
    private static func localizedString(format: String,
                                arguments: [TXNativeObjcArgument]) -> String {
        var args : [Any] = []
        
        for argument in arguments {
            
            switch argument.type {
            case .int:
                if let number = argument.value as? NSNumber {
                    args.append(number.intValue)
                }
            case .unsigned:
                if let number = argument.value as? NSNumber {
                    args.append(number.uintValue)
                }
            case .double:
                if let number = argument.value as? NSNumber {
                    args.append(number.doubleValue)
                }
            case .char,
                 .cString,
                 .object,
                 .percent:
                if let string = argument.value as? String {
                    args.append(string)
                }
            // We include the invalid case, so that the error is visible in the
            // UI.
            case .invalid:
                if let string = argument.value as? String {
                    args.append(string)
                }
            @unknown default:
                continue
            }
        }
        
        return localizedString(format: format,
                               arguments: args)
    }
}
