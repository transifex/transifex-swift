//
//  Rendering.swift
//  Transifex
//
//  Created by Dimitrios Bendilas on 2/10/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

/// A protocol for classes that determine what translation is returned when the requested translation is not
/// available.
///
/// Can be used in multiple cases, such as when the translation is not found.
@objc
public protocol TXMissingPolicy {

    /// Return a string as a translation based on the given source string.
    ///
    /// Classes that conform to this protocol may choose to return anything relevant to the given source
    /// string or not, based on their custom policy.
    ///
    /// - Parameter sourceString: the source string
    func get(sourceString: String) -> String
}

/// Returns the source string when the translation string is missing.
public final class TXSourceStringPolicy : NSObject, TXMissingPolicy {
    
    /// Return the source string as the translation string.
    /// - Parameter sourceString: the source string
    /// - Returns: the source string
    public func get(sourceString: String) -> String {
        return sourceString
    }
}

/// Returns a string that looks like the source string but contains accented characters.
///
/// Example:
/// `PseudoTranslationPolicy().get("The quick brown fox")`
/// Returns:
/// `Ťȟê ʠüıċǩ ƀȓøẁñ ƒøẋ`
public final class TXPseudoTranslationPolicy : NSObject, TXMissingPolicy {
    
    let TABLE = [
        "A": "Å", "B": "Ɓ", "C": "Ċ", "D": "Đ",
        "E": "Ȅ", "F": "Ḟ", "G": "Ġ", "H": "Ȟ",
        "I": "İ", "J": "Ĵ", "K": "Ǩ", "L": "Ĺ",
        "M": "Ṁ", "N": "Ñ", "O": "Ò", "P": "Ƥ",
        "Q": "Ꝗ", "R": "Ȓ", "S": "Ș", "T": "Ť",
        "U": "Ü", "V": "Ṽ", "W": "Ẃ", "X": "Ẍ",
        "Y": "Ẏ", "Z": "Ž",
        "a": "à", "b": "ƀ", "c": "ċ", "d": "đ",
        "e": "ê", "f": "ƒ", "g": "ğ", "h": "ȟ",
        "i": "ı", "j": "ǰ", "k": "ǩ", "l": "ĺ",
        "m": "ɱ", "n": "ñ", "o": "ø", "p": "ƥ",
        "q": "ʠ", "r": "ȓ", "s": "š", "t": "ť",
        "u": "ü", "v": "ṽ", "w": "ẁ", "x": "ẋ",
        "y": "ÿ", "z": "ź",
    ]
    
    /// Return a string that looks somewhat like the source string.
    ///
    /// - Parameter sourceString: the source string
    /// - Returns: a string that looks like the source string
    public func get(sourceString: String) -> String {
        var str = sourceString
        for (ascii, accented) in self.TABLE {
            str = str.replacingOccurrences(of: ascii, with: accented)
        }
        return str
    }
}

/// Wraps the returned string with a custom format.
///
/// Example:
/// `WrappedStringPolicy(">>", "<<").get("Click here")`
/// Returns:
/// `>>Click here<<`
public final class TXWrappedStringPolicy : NSObject, TXMissingPolicy {

    var start: String?
    var end: String?
    
    /**
     Constructor.

     - start: an optional string to prepend to the source string
     - end: an optional string to append to the source string
     */
    @objc
    public init(start: String? = nil, end: String? = nil) {
        self.start = start
        self.end = end
    }

    /**
     Return a string that wraps the source string.
     */
    public func get(sourceString: String) -> String {
        let start = self.start ?? "]"
        let end = self.end ?? "]"
        return "\(start)\(sourceString)\(end)"
    }
}

/**
 Combines multiple policies to create a complex result.
 
 The result of each policy if fed to the next as source.
 */
public final class TXCompositePolicy : NSObject, TXMissingPolicy {
    
    var policies: [TXMissingPolicy] = []
    
    /// Constructor.
    ///
    /// The order of the policies is important; the result of each policy is fed to the next one.
    ///
    /// - Parameter policies: The missing policies to be used.
    public init(_ policies: TXMissingPolicy...) {
        self.policies = policies
    }
    
    /// Objective-C friendly constructor for passing MissingPolicy objects as an array.
    ///
    /// The order of the policies is important; the result of each policy is fed to the next one.
    ///
    /// - Parameter policies: The missing policies to be used.
    @objc
    public init(_ policies: [TXMissingPolicy]) {
        self.policies = policies
    }
    
    /// Returns a string after it has been fed to all of the provided policies sequentially.
    ///
    /// - Parameter sourceString: The source string
    /// - Returns: The final string
    public func get(sourceString: String) -> String {
        var str: String = sourceString
        for policy in policies {
            str = policy.get(sourceString: str)
        }
        return str
     }
}

/**
 Defines an interface for error policy classes.
 
 Error policies define what happens when rendering faces an error.
 They are useful to protect the user from pages failing to load.
 */
@objc
public protocol TXErrorPolicy {
    
    /// Return the error string to be displayed using all the information provided by the SDK.
    ///
    /// - Parameters:
    ///   - sourceString: The source string
    ///   - stringToRender: The string to render as provided by the cache
    ///   - localeCode: The locale code
    ///   - params: Any extra parameters that were passed along with the source string
    func get(sourceString: String,
             stringToRender: String,
             localeCode: String,
             params: [String: Any]) -> String
}

/**
 An error policy that simply returns the source string instead of the translation.
 */
public final class TXRenderedSourceErrorPolicy : TXErrorPolicy {
    
    public func get(sourceString: String,
                    stringToRender: String,
                    localeCode: String,
                    params: [String: Any]) -> String {
        return sourceString
    }
}
