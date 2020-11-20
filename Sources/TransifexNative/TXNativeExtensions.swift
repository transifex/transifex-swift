//
//  TXNativeExtensions.swift
//  TransifexNative
//
//  Created by Stelios Petrakis on 16/11/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

// Note:
// Please copy this file to your project and add it to all of the app's targets
// if you are making use of either of the following Swift methods:
//
// * NSString.localizedStringWithFormat()
// * String.localizedStringWithFormat()
//
// If your code makes use of the Objective-C's
// [NSString localizedStringWithFormat:...] method, you don't need to copy this
// file.

import Foundation
import TransifexNative

/// Override Swift String.localizedStringWithFormat: method
public extension String {
    static func localizedStringWithFormat(
        _ format: String, _ arguments: CVarArg...
    ) -> String {
        guard let localized = TxNative.localizedString(format: format,
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
        guard let localized = TxNative.localizedString(format: format as String,
                                                       arguments: args) as? Self else {
            return withVaList(args) {
                self.init(format: format as String, locale: Locale.current,
                          arguments: $0)
            }
        }
        
        return localized
    }
}
