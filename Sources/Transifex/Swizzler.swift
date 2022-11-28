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
class SwizzledBundle : Bundle {
    override func localizedString(forKey key: String,
                                  value: String?,
                                  table tableName: String?) -> String {
        if Swizzler.activated && value != Swizzler.SKIP_SWIZZLING_VALUE {
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
        
        activate(bundles: Bundle.allBundles)
        
        TXNativeObjcSwizzler.activate {
            return self.localizedString(format: $0,
                                        arguments: $1)
        }
        
        activated = true
    }
    
    /// Swizzles the passed bundles so that their localization methods are intercepted.
    ///
    /// - Parameter bundles: The Bundle that will be swizzled
    internal static func activate(bundles: [Bundle]) {
        bundles.forEach({ (bundle) in
            guard !bundle.isKind(of: SwizzledBundle.self) else {
                return
            }
            object_setClass(bundle, SwizzledBundle.self)
        })
    }
    
    /// Centralized method that all swizzled or overriden localizedStringWithFormat: methods will call once
    /// Swizzler is activated.
    ///
    /// - Parameters:
    ///   - format: The format string
    ///   - arguments: An array of arguments of arbitrary type
    /// - Returns: The final string
    static func localizedString(format: String,
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
