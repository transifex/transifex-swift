//
//  File.swift
//  
//
//  Created by Dimitrios Bendilas on 2/8/20.
//

import Foundation

/**
 Represents a string in the source locale, along with all its properties.
 */
class SourceString : CustomStringConvertible {
    
    /// The string itself
    var string: String = ""
    
    /// A unique identifier for the string
    var key: String = ""
    
    /// An optional list of strings that give extra information about the string.
    var context: [String] = []
    
    /// A dictionary with metadata that accompany the string
    var meta: [String:Any] = [:]
    
    /// A list of strings that provide information about the places where this string
    /// can be found, e.g. a list of `.swift` filenames of a project
    var occurrences: [String] = []
    
    /**
     An optional comment that gives extra context to the translators, in order to write
     a better translation for this string.
     */
    var comment: String? {
        get { return meta["_comment"] as? String }
    }
    
    /**
     An optional integer that tells translators how long the translation can be for this string.
     */
    var characterLimit: Int? {
        get { return meta["_charlimit"] as? Int }
    }
    
    /**
     An optional list of strings that give extra information on this string, often used
     for aiding the automation of the localization workflow.
     */
    var tags: [String] {
        get { return meta["_tags", default: []] as! [String] }
    }
    
    init(_ string: String, key: String, context: [String] = [], meta: [String: Any] = [:]) {
        self.string = string
        self.key = key
        self.context = context
        self.meta = meta
    }
    
    /**
     Add a new occurrence for the string.
     - occurrence: a place where this string is found, e.g. a file name
     */
    func addOccurrence(_ occurrence: String) {
        occurrences.append(occurrence)
    }
    
    public var description: String {
        return "SourceString(\(string), key: \(key), context: \(context), meta: \(meta), occurrences: \(occurrences)"
    }
    
}
