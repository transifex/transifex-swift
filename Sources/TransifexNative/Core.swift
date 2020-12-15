//
//  Core.swift
//  TransifexNative
//
//  Created by Dimitrios Bendilas on 17/7/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

import Foundation

/// Protocol used to pass NativeCore as depedency injection in the Swizzler class.
internal protocol TranslationProvider {
    func translate(sourceString: String,
                   params: [String: Any]) -> String
}

/// The rendering strategy to be used when TransifexNative renders the final string.
@objc
public enum RenderingStategy : Int {
    case icu
    case platform
}

/// The main class of the framework, responsible for orchestrating all functionality.
class NativeCore : TranslationProvider {
    var cache: TXCache
    var locales: LocaleState
    var cdsHandler: CDSHandler
    var missingPolicy: MissingPolicy
    var errorPolicy: ErrorPolicy
    var renderingStrategy : RenderingStategy
    
    /// Create an instance of the core framework class.
    ///
    /// - Parameters:
    ///   - locales: a list of locale codes for the languages configured in the application
    ///   - token: the API token to use for connecting to the CDS
    ///   - secret: the additional secret to use for pushing source content
    ///   - cdsHost: an optional host for the Content Delivery Service, defaults to the host provided by
    ///   Transifex
    ///   - cache: the translation cache that holds the translations from the CDS
    ///   - missingPolicy: an optional policy to use for returning strings when a translation is missing
    ///   - errorPolicy: an optional policy to determine how to handle rendering errors
    ///   - renderingStrategy: determines which strategy to be used when rendering the final
    ///   string.
    init(
        locales: LocaleState,
        token: String,
        secret: String?,
        cdsHost: String?,
        cache: TXCache?,
        missingPolicy: MissingPolicy? = nil,
        errorPolicy: ErrorPolicy? = nil,
        renderingStrategy : RenderingStategy
    ) {
        self.locales = locales
        self.cdsHandler = CDSHandler(
            localeCodes: self.locales.translatedLocales,
            token: token,
            secret: secret,
            cdsHost: cdsHost
        )
        self.cache = cache ?? TXDefaultCache()
        self.missingPolicy = missingPolicy ?? SourceStringPolicy()
        self.errorPolicy = errorPolicy ?? RenderedSourceErrorPolicy()
        self.renderingStrategy = renderingStrategy
        
        Swizzler.activate(translationProvider: self)
    }
    
    /// Fetch translations from CDS and store them in the cache.
    ///
    /// - Parameter localeCode: an optional locale to fetch translations from; if none provided, it
    /// will fetch translations for all locales defined in the configuration
    func fetchTranslations(_ localeCode: String? = nil,
                           completionHandler: PullCompletionHandler? = nil) {
        cdsHandler.fetchTranslations(localeCode: localeCode) { (translations, errors) in
            if errors.count == 0 {
                self.cache.update(translations: translations,
                                  replaceEntries: true)
            }
            else {
                print("\(#function) Errors: \(errors)")
            }
            
            completionHandler?(translations, errors)
        }
    }
    
    /// Pushes the base translations to CDS.
    ///
    /// - Parameters:
    ///   - translations: A list of `TxSourceString` objects.
    ///   - purge: Whether to replace the entire resource  content (true) or not (false). Defaults to false.
    ///   - completionHandler: A callback to be called when the push operation is complete with a
    /// boolean argument that informs the caller that the operation was successful (true) or not (false).
    func pushTranslations(_ translations: [TxSourceString],
                          purge: Bool = false,
                          completionHandler: @escaping (Bool) -> Void) {
        cdsHandler.pushTranslations(translations,
                                    purge: purge,
                                    completionHandler: completionHandler)
    }
    
    /// Used by the Swift localizedString(format:arguments:) methods found in the
    /// TXExtensions.swift file.
    func localizedString(format: String,
                          arguments: [Any]) -> String {
        return Swizzler.localizedString(format: format,
                                        arguments: arguments)
    }
    
    /// TranslationProvider protocol method used by Swizler class.
    func translate(sourceString: String, params: [String : Any]) -> String {
        return translate(sourceString: sourceString,
                         localeCode: nil,
                         params: params,
                         context: nil)
    }
    
    /// Return the translation of the given source string on a certain locale.
    ///
    /// - Parameters:
    ///   - sourceString: the string in the source locale
    ///   - localeCode: an optional locale to translate to; defaults to the current app locale
    ///   - params: a dictionary with optional parameters to use for rendering a string
    ///   e.g. variable placeholders, character limit, etc
    ///   - context: an optional context that describes the source string (comma separated strings)
    /// - Returns: the final string to display to the user
    func translate(sourceString: String,
                   localeCode: String? = nil,
                   params: [String: Any],
                   context: String?) -> String {
        var translationTemplate: String?
        let localeToRender = localeCode ?? self.locales.currentLocale
        let isSource = self.locales.isSource(localeToRender)
        
        // If the app uses its source locale or if the key is not found in cache
        // and the Swizzled value in the params dictionary exists, then use this
        // one. Otherwise fallback to the sourceString.
        //
        // This is done so that for the swizzled storyboard methods, the logic
        // doesn't fallback to the key (which is typically a non-human readable
        // id) but to the value, which is provided by the developer in the
        // storyboard file.
        //
        // In the NSLocalizedString() call case those, we want to fallback to
        // the first argument of that method which is the key, as there's no
        // value provided.
        var fallbackValue = sourceString
        
        if let paramValue = params[Swizzler.PARAM_VALUE_KEY] as? String {
            fallbackValue = paramValue
        }
        
        if isSource {
            translationTemplate = fallbackValue
        }
        else {
            let key = generateKey(sourceString: sourceString,
                                  context: context)
            translationTemplate = cache.get(key: key,
                                            localeCode: localeToRender)
            if translationTemplate == nil {
                return missingPolicy.get(sourceString: fallbackValue)
            }
        }
        
        return render(
            sourceString: sourceString,
            stringToRender: translationTemplate,
            localeCode: localeToRender,
            params: params
        )
    }
    
    /// Renders the translation to the current format, taking into account any variable placeholders.
    ///
    /// Delegates the rendering to the appropriate rendering strategy (ICU or platform).
    ///
    /// - Parameters:
    ///   - sourceString: the string in the source locale
    ///   - stringToRender: the optional translation template
    ///   - localeCode: the locale to translate to
    ///   - params: a dictionary with parameters to use for rendering a string
    /// - Returns: the final string to display to the user
    func render(sourceString: String,
                stringToRender: String?,
                localeCode: String,
                params: [String: Any]) -> String {
        let stringToRender = stringToRender ?? sourceString
        
        switch renderingStrategy {
        case .icu:
            return ICUMessageFormat.format(stringToRender: stringToRender,
                                           localeCode: localeCode,
                                           params: params)
        case .platform:
            return PlatformFormat.format(stringToRender: stringToRender,
                                           localeCode: localeCode,
                                           params: params)
        }
    }
}

/// A static class that is the main point of entry for all the functionality of Transifex Native throughout the SDK.
public final class TxNative : NSObject {
    /// The filename of the file that holds the translated strings and it's bundled inside the app.
    public static let STRINGS_FILENAME = "txstrings.json"
    
    /// An instance of the core class that handles all the work
    private static var tx : NativeCore?
    
    /// The available and current locales
    @objc
    public static var locales: LocaleState? {
        get {
            tx?.locales
        }
    }

    /// Static constructor.
    ///
    /// - Parameters:
    ///   - locales: keeps track of the available and current locales
    ///   - token: the Transifex token that can be used for retrieving translations from CDS
    ///   - secret: the Transifex secret that can be used for pushing source strings to CDS
    ///   - cdsHost: the host of the CDS service; defaults to a production CDS service hosted by
    ///   Transifex
    ///   - cache: holds the available translations in various locales. If nil (default) the internal cache
    ///   mechanism will be activated, otherwise the provided cache will be used.
    ///   - missingPolicy: determines how to handle translations that are not available
    ///   - errorPolicy: determines how to handle exceptions when rendering a problematic
    ///   translation
    ///   - renderingStrategy: determines which strategy to be used when rendering the final
    ///   string; defaults to platform strategy
    @objc
    public static func initialize(
        locales: LocaleState,
        token: String,
        secret: String?,
        cdsHost: String? = nil,
        cache: TXCache? = nil,
        missingPolicy: MissingPolicy? = nil,
        errorPolicy: ErrorPolicy? = nil,
        renderingStrategy: RenderingStategy = .platform
    ) {
        guard tx == nil else {
            print("Transifex Native is already initialized")
            return
        }

        tx = NativeCore(locales: locales,
                        token: token,
                        secret: secret,
                        cdsHost: cdsHost,
                        cache: cache,
                        missingPolicy: missingPolicy,
                        errorPolicy: errorPolicy,
                        renderingStrategy: renderingStrategy)
    }
    
    /// Return the translation of the given source string on a certain locale.
    ///
    /// - Parameters:
    ///   - sourceString: the string in the source locale
    ///   - localeCode: an optional locale to translate to; defaults to the current app locale
    ///   - params: a dictionary with optional parameters to use for rendering a string
    ///   e.g. variable placeholders, character limit, etc
    ///   - context: an optional context that describes the source string (comma separated strings)
    /// - Returns: the final string to display to the user
    @objc
    public static func translate(sourceString: String,
                                 localeCode: String? = nil,
                                 params: [String: Any],
                                 context: String?
    ) -> String? {
        return tx?.translate(
            sourceString: sourceString,
            localeCode: localeCode,
            params: params,
            context: context
        )
    }
    
    /// Used by the Swift localizedString(format:arguments:) methods found in the
    /// TXExtensions.swift file.
    public static func localizedString(format: String,
                                       arguments: [Any]) -> String? {
        return tx?.localizedString(format: format,
                                   arguments: arguments)
    }
    
    /// Fetches the translations from CDS.
    ///
    /// - Parameter localeCode: if not provided, it will fetch translations for all locales defined in the
    /// app configuration.
    @objc
    public static func fetchTranslations(_ localeCode: String? = nil,
                                         completionHandler: PullCompletionHandler? = nil) {
        tx?.fetchTranslations(localeCode,
                              completionHandler: completionHandler)
    }
    
    /// Pushes the base translations to CDS.
    ///
    /// - Parameters:
    ///   - translations: A list of `TxSourceString` objects.
    ///   - purge: Whether to replace the entire resource content (true) or not (false). Defaults to false.
    ///   - completionHandler: A callback to be called when the push operation is complete with a
    /// boolean argument that informs the caller that the operation was successful (true) or not (false).
    @objc
    public static func pushTranslations(_ translations: [TxSourceString],
                                        purge: Bool = false,
                                        completionHandler: @escaping (Bool) -> Void) {
        tx?.pushTranslations(translations,
                             purge: purge,
                             completionHandler: completionHandler)
    }
}

/// TODO: This function is probably unnecessary; callers could instead use
/// TxNative.translate() directly
public func t(_ string: String,
              context: String? = nil,
              params: [String: Any] = [:]) -> String? {
    return TxNative.translate(
        sourceString: string,
        params: params,
        context: context
    )
}
