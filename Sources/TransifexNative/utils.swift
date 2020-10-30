//
//  utils.swift
//  TransifexNative
//
//  Created by Dimitrios Bendilas on 2/8/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation
import CommonCrypto

/// Return a unique key, based on the given source string and optional context.
///
/// A string can be associated with multiple context values, so the context argument can be a serialized
/// comma-separated string or a single string.
///
/// - Parameters:
///   - sourceString: the actual string
///   - context: an optional context that accompanies the string
/// - Returns: a hash that uniquely identifies the string
func generateKey(sourceString: String, context: String?) -> String {
    var context: String = context ?? ""
    context = context.replacingOccurrences(of: ",", with: ":")
    let finalString = sourceString + ":" + context
    return finalString.md5()
}

extension String {
    func md5() -> String {
        let data = Data(utf8)
        var hash = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_MD5(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return hash.map { String(format: "%02hhx", $0) }.joined()
    }
}
