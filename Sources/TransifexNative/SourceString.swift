//
//  SourceString.swift
//  TransifexNative
//
//  Created by Dimitrios Bendilas on 2/8/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

/// Represents the metadata that accompany a SourceString
struct SourceStringMeta : Codable {
    var context : [String]?
    var comment : String?
    var characterLimit : Int?
    var tags : [String]?
    
    enum CodingKeys : String, CodingKey {
        case context
        case comment = "developer_comment"
        case characterLimit = "character_limit"
        case tags
    }
}

extension SourceStringMeta : CustomDebugStringConvertible {
    var debugDescription: String {
        """
SourceStringMeta(tags: \(tags?.debugDescription ?? "Not set"), \
context: \(context?.debugDescription ?? "Not set"), \
comment: \(comment ?? "Not set"), \
characterLimit: \(characterLimit?.description ?? "Not set"))
"""
    }
}

/// Represents a string in the source locale, along with all its properties.
struct SourceString : Codable {
    
    /// The string itself.
    var string : String
    
    /// A unique identifier for the string.
    var key : String = ""
    
    /// A dictionary with metadata that accompany the string.
    var meta : SourceStringMeta?

    /// An optional list of strings that give extra information about the string.
    var context : [String]? {
        get { return meta?.context }
    }
    
    /// An optional comment that gives extra context to the translators, in order to write a better translation
    /// for this string.
    var comment : String? {
        get { return meta?.comment }
    }
    
    /// An optional integer that tells translators how long the translation can be for this string.
    var characterLimit: Int? {
        get { return meta?.characterLimit }
    }
    
    /// An optional list of strings that give extra information on this string, often used for aiding the
    /// automation of the localization workflow.
    var tags: [String]? {
        get { return meta?.tags }
    }
    
    /// A list of strings that provide information about the places where this string can be found.
    /// e.g. a list of `.swift` filenames of a project
    var occurrences : [String] = []
    
    /// Adds a new occurence for the string.
    ///
    /// - Parameter occurrence: a place where this string is found, e.g. a file name
    mutating func addOccurrence(_ occurrence : String) {
        occurrences.append(occurrence)
    }
    
    enum CodingKeys : String, CodingKey {
        case string, meta
    }
}

extension SourceString : CustomDebugStringConvertible {
    var debugDescription: String {
        """
SourceString(string: \(string), \
key: \(key), \
meta: \(meta?.debugDescription ?? "Not set"), \
occurrences: \(occurrences))
"""
    }
}
