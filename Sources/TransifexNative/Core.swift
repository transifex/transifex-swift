//
//  core.swift
//  toolkit
//
//  Created by Dimitrios Bendilas on 17/7/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

/**
 The main class of the framework, responsible for orchestrating all functionality.
 */
public class NativeCore {
    
    var cache: Cache = MemoryCache()
    var locales: LocaleState = LocaleState()
    var cdsHandler: CDSHandler? = nil
    var missingPolicy: MissingPolicy = SourceStringPolicy()
    var errorPolicy: ErrorPolicy = RenderedSourceErrorPolicy()
    var initialized = false
    
    init() {
        
    }
    /**
     Create an instance of the core framework class.

     Also warms up the cache by fetching the translations from the CDS.

     - localeCodes: a list of locale codes for the languages configured in the application
     - token: the API token to use for connecting to the CDS
     - secret: the additional secret to use for pushing source content
     - cds_host: an optional host for the Content Delivery Service, defaults to the host provided by Transifex
     - missingPolicy: an optional policy to use for returning strings when a translation is missing
     - errorPolicy: an optional policy to determine how to handle rendering errors
     */
    func initialize(
        locales: LocaleState,
        token: String,
        secret: String?,
        cdsHost: String?,
        cache: Cache?,
        missingPolicy: MissingPolicy? = nil,
        errorPolicy: ErrorPolicy? = nil
    ) {
        self.locales = locales
        self.cdsHandler = CDSHandler(
            localeCodes: self.locales.appLocales,
            token: token,
            secret: secret,
            cdsHost: cdsHost
        )
        if cache != nil {
            self.cache = cache!
        }
        if missingPolicy != nil {
            self.missingPolicy = missingPolicy!
        }
        if errorPolicy != nil {
            self.errorPolicy = errorPolicy!
        }
        initialized = true
    }
    
    /**
     Fetch translations from CDS and store them in the cache.
     
       - localeCode: an optional locale to fetch translations from; if none provided it will fetch translations for all locales defined in the configuration
     */
    public func fetchTranslations(_ localeCode: String? = nil) {
        self.cdsHandler!.fetchTranslations { (translations: [String : LocaleStrings], error: Error?) in
            for (localeCode, localeTranslations) in translations {
                self.cache.update(localeCode: localeCode, translations: localeTranslations)
            }
        }
    }
    
    /**
     Return the translation of the given source string on a certain locale.
     
     - sourceString: the string in the source locale
     - localeCode: an optional locale to translate to; defaults to the current app locale
     - params: a dictionary with optional parameters to use for rendering a string
       e.g. variable placeholders, character limit, etc
     - context: an optional context that describes the source string (comma separated strings)
     - return: the final string to display to the user
     */
    func translate(sourceString: String, localeCode: String? = nil, params: [String: Any], context: String?) -> String {
        var translationTemplate: String?
        let localeToRender = localeCode != nil ? localeCode! : self.locales.currentLocale
        let isSource = self.locales.isSource(localeToRender)
        if isSource {
          translationTemplate = sourceString
        }
        else {
            let key = generateKey(sourceString: sourceString, context: context)
            translationTemplate = cache.get(key: key, localeCode: localeToRender)
            if translationTemplate == nil {
                return missingPolicy.get(sourceString: sourceString)
            }
        }
        
        return render(
            sourceString: sourceString,
            stringToRender: translationTemplate,
            localeCode: localeToRender,
            params: params
        )
    }
    
    /**
     Renders the translation to the current format, taking into account any variable placeholders.
     
     Delegates the rendering to the appropriate rendering strategy (ICU or platform).
     */
    func render(sourceString: String, stringToRender: String?, localeCode: String, params: [String: Any]) -> String {
        // TODO: Implement the platform strategy
        return ICUMessageFormat.format(stringToRender: stringToRender ?? sourceString, localeCode: localeCode, params: params)
    }
    
}

/**
 A static class that is the main point of entry for all the functionality of Transifex Native
 throughout the SDK.
 */
public final class TxNative {
    
    /// An instance of the core class that handles all the work
    static var tx = NativeCore()
    
    private init() { }
    
    public static var locales: LocaleState {
        get { tx.locales }
    }

    /**
     Static constructor.
     
     - locales: keeps track of the available and current locales
     - token: the Transifex token that can be used for retrieving translations from CDS
     - secret: the Transifex secret that can be used for pushing source strings to CDS
     - cdsHost: the host of the CDS service; defaults to a production CDS service hosted by Transifex
     - cache: holds the available translations in various locales
     - missingPolicy: determines how to handle translations that are not available
     - errorPolicy: determines how to handle exceptions when rendering a problematic translation
     */
    public static func initialize(
        locales: LocaleState,
        token: String,
        secret: String?,
        cdsHost: String?,
        cache: Cache? = nil,
        missingPolicy: MissingPolicy? = nil,
        errorPolicy: ErrorPolicy? = nil
    ) {
        if tx.initialized { return }
        tx.initialize(
            locales: locales,
            token: token,
            secret: secret,
            cdsHost: cdsHost,
            cache: cache,
            missingPolicy: missingPolicy,
            errorPolicy: errorPolicy
        )
    }
    
    /**
     Return the translation of the given source string on a certain locale.
     
     - sourceString: the string in the source locale
     - localeCode: an optional locale to translate to; defaults to the current app locale
     - params: a dictionary with optional parameters to use for rendering a string
       e.g. variable placeholders, character limit, etc
     - context: an optional context that describes the source string (comma separated strings)
     - return: the final string to display to the user
     */
    public static func translate(sourceString: String, localeCode: String? = nil, params: [String: Any], context: String?) -> String {
        return tx.translate(
            sourceString: sourceString,
            localeCode: localeCode,
            params: params,
            context: context
        )
    }
    
    /**
     Fetches the translations from CDS.
     
     - localeCode: if not provided, it will fetch translations for all locales defined in the app configuration
     */
    public static func fetchTranslations(_ localeCode: String? = nil) {
        tx.fetchTranslations(localeCode)
    }
}

// TODO: This function is probably unnecessary; callers could instead use TxNative.translate() directly
public func t(_ string: String, context: String? = nil, params: [String: Any] = [:]) -> String {
    return TxNative.translate(
        sourceString: string,
        params: params,
        context: context
    )
}

