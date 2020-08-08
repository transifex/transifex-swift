//
//  File.swift
//  
//
//  Created by Dimitrios Bendilas on 2/8/20.
//

import Foundation
import CryptoKit

/**
 Return a unique key based on the given source string and optional context.
 
 A string can be associated with multiple context values, so the context
 argument can be a serialized comma-separated string or a single string.
 
   - sourceString: the actual string
   - context: an optional context that accompanies the string
   - return: a hash that uniquely identifies the string
 */
func generateKey(sourceString: String, context: String?) -> String {
    var context: String = context ?? ""
    context = context.replacingOccurrences(of: ",", with: ":")
    let finalString = sourceString + ":" + context
    let digest = Insecure.MD5.hash(data: finalString.data(using: .utf8)!)
    return digest.map {
        String(format: "%02hhx", $0)
    }.joined()
}
