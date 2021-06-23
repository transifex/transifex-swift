//
//  Core.swift
//  Transifex
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

/// The rendering strategy to be used when Transifex renders the final string.
@objc
public enum TXRenderingStategy : Int {
    /// Platform strategy, default one
    case platform
    /// ICU platform strategy, currently not implemented
    case icu
}

/// Bypasses swizzling and offers the bundled translation for the passed locale, if found.
///
/// If the string is not found the logic returns the value of the `params` dictionary and if this is
/// also not found, it returns the `sourceString`.
///
/// This logic is used when the app needs to access its source localization or when a string for the
/// requested localization is not found and the missing policy is about to be called. Due to the fact
/// that CDS doesn't provide a way to download the source localizations, the SDK needs to look into
/// the bundled translations for the source locale and use those translations instead.
final class BypassLocalizer {
    let bundle : Bundle?
    
    /// Initializes bypass localizer with a certain locale.
    ///
    /// - Parameter localeCode: The locale to be used
    init(with localeCode: String) {
        /// Get the bundle for the provided locale code, if it exists.
        guard let bundlePath = Bundle.main.path(forResource: localeCode,
                                                ofType: "lproj") else {
            self.bundle = nil
            return
        }

        self.bundle = Bundle(path: bundlePath)
    }
    
    private func extractBundledString(sourceString: String,
                                      params: [String: Any]) -> String? {
        guard let bundle = bundle else {
            return nil
        }
        
        let tableName = params[Swizzler.PARAM_TABLE_KEY] as? String
        
        // We use the SKIP_SWIZZLING_VALUE constant to skip swizzling for this
        // call, so that the actual value can be retrieved, if it exists in the
        // application bundle.
        let localizedString = bundle.localizedString(forKey: sourceString,
                                                     value: Swizzler.SKIP_SWIZZLING_VALUE,
                                                     table: tableName)
        
        if  localizedString != Swizzler.SKIP_SWIZZLING_VALUE {
            return localizedString
        }
  
        return nil
    }
    
    func get(sourceString: String, params: [String: Any]) -> String {
        if let bundledString = extractBundledString(sourceString: sourceString,
                                                    params: params) {
            return bundledString
        }
        
        if let paramValue = params[Swizzler.PARAM_VALUE_KEY] as? String {
            return paramValue
        }
        
        return sourceString
    }
}

/// The main class of the framework, responsible for orchestrating all functionality.
class NativeCore : TranslationProvider {
    var cache: TXCache
    var locales: TXLocaleState
    var cdsHandler: CDSHandler
    var missingPolicy: TXMissingPolicy
    var errorPolicy: TXErrorPolicy
    var renderingStrategy : TXRenderingStategy
    var bypassLocalizer : BypassLocalizer
    
    /// Create an instance of the core framework class.
    ///
    /// - Parameters:
    ///   - locales: a list of locale codes for the languages configured in the application
    ///   - token: the API token to use for connecting to the CDS
    ///   - secret: the additional secret to use for pushing source content
    ///   - cdsHost: an optional host for the Content Delivery Service, defaults to the host provided by
    ///   Transifex
    ///   - cache: the translation cache that holds the translations from the CDS
    ///   - session: Optional URLSession to be used for all the requests made to the CDS service. If
    ///   no session is provided, an ephemeral URLSession with no cache will be created and used
    ///   - missingPolicy: an optional policy to use for returning strings when a translation is missing
    ///   - errorPolicy: an optional policy to determine how to handle rendering errors
    ///   - renderingStrategy: determines which strategy to be used when rendering the final
    ///   string.
    init(
        locales: TXLocaleState,
        token: String,
        secret: String?,
        cdsHost: String?,
        cache: TXCache?,
        session: URLSession? = nil,
        missingPolicy: TXMissingPolicy? = nil,
        errorPolicy: TXErrorPolicy? = nil,
        renderingStrategy : TXRenderingStategy
    ) {
        self.locales = locales
        self.cdsHandler = CDSHandler(
            localeCodes: self.locales.translatedLocales,
            token: token,
            secret: secret,
            cdsHost: cdsHost,
            session: session
        )
        self.cache = cache ?? TXStandardCache.getCache()
        self.missingPolicy = missingPolicy ?? TXSourceStringPolicy()
        self.errorPolicy = errorPolicy ?? TXRenderedSourceErrorPolicy()
        self.renderingStrategy = renderingStrategy
        self.bypassLocalizer = BypassLocalizer(with: locales.sourceLocale)
        
        Swizzler.activate(translationProvider: self)
    }
    
    /// Fetch translations from CDS and store them in the cache.
    ///
    /// - Parameter localeCode: an optional locale to fetch translations from; if none provided, it
    /// will fetch translations for all locales defined in the configuration
    /// - Parameter tags: An optional list of tags so that only strings that have all of the given tags are fetched.
    /// - Parameter completionHandler: The completion handler that informs the caller with the
    /// new translations and a list of possible errors that might have occured
    func fetchTranslations(_ localeCode: String? = nil,
                           tags: [String]? = nil,
                           completionHandler: TXPullCompletionHandler? = nil) {
        cdsHandler.fetchTranslations(localeCode: localeCode) { (translations, errors) in
            if errors.count > 0 {
                Logger.error("\(#function) Errors: \(errors)")
            }

            self.cache.update(translations: translations)

            completionHandler?(translations, errors)
        }
    }
    
    /// Pushes the base translations to CDS.
    ///
    /// - Parameters:
    ///   - translations: A list of `TXSourceString` objects.
    ///   - purge: Whether to replace the entire resource  content (true) or not (false). Defaults to false.
    ///   - completionHandler: A callback to be called when the push operation is complete with a
    /// boolean argument that informs the caller that the operation was successful (true) or not (false).
    func pushTranslations(_ translations: [TXSourceString],
                          purge: Bool = false,
                          completionHandler: @escaping (Bool) -> Void) {
        cdsHandler.pushTranslations(translations,
                                    purge: purge,
                                    completionHandler: completionHandler)
    }
    
    /// Forces CDS cache invalidation.
    ///
    /// - Parameter completionHandler: A callback to be called when force cache invalidation is
    /// complete with a boolean argument that informs the caller that the operation was successful (true) or
    /// not (false).
    func forceCacheInvalidation(completionHandler: @escaping (Bool) -> Void) {
        cdsHandler.forceCacheInvalidation(completionHandler: completionHandler)
    }
    
    /// Used by the Swift localizedString(format:arguments:) methods found in the
    /// TXExtensions.swift file.
    func localizedString(format: String,
                          arguments: [Any]) -> String {
        return Swizzler.localizedString(format: format,
                                        arguments: arguments)
    }
    
    /// TranslationProvider protocol method used by Swizzler class.
    func translate(sourceString: String, params: [String : Any]) -> String {
        /// If this call call originates from a `localizedStringWithFormat` swizzled method, it will
        /// contain the extra arguments. In that case the first argument of those methods (format) would
        /// have already been resolved by a `NSLocalizedString()` call, so we should not perform
        /// a second lookup on the cache, we can proceed by directly rendering the string and let the
        /// `render()` method extract the ICU plurals.
        if params[Swizzler.PARAM_ARGUMENTS_KEY] != nil {
            return render(sourceString: sourceString,
                          stringToRender: nil,
                          localeCode: self.locales.currentLocale,
                          params: params)
        }
        else {
            return translate(sourceString: sourceString,
                             localeCode: nil,
                             params: params,
                             context: nil)
        }
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
        
        /// If the source locale is requested, or if the source string is missing from cache,
        /// the bypass localizer is used, to look up on the application bundle and fetch the
        /// localized content for the source locale (if found) by bypassing swizzling.
        
        if isSource {
            translationTemplate = self.bypassLocalizer.get(sourceString: sourceString,
                                                           params: params)
        }
        else {
            let key = txGenerateKey(sourceString: sourceString,
                                    context: context)
            translationTemplate = cache.get(key: key,
                                            localeCode: localeToRender)
            if !String.containsTranslation(translationTemplate) {
                let bypassedString = self.bypassLocalizer.get(sourceString: sourceString,
                                                              params: params)
                
                return missingPolicy.get(sourceString: bypassedString)
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
        
        do {
            switch renderingStrategy {
            case .icu:
                return try ICUMessageFormat.format(stringToRender: stringToRender,
                                                   localeCode: localeCode,
                                                   params: params)
            case .platform:
                return try PlatformFormat.format(stringToRender: stringToRender,
                                                 localeCode: localeCode,
                                                 params: params)
            }
        }
        catch {
            Logger.error("""
Error rendering source string '\(sourceString)' with string to render '\(stringToRender)'
 locale code: \(localeCode) params: \(params). Error: \(error)
""")
            return errorPolicy.get(sourceString: sourceString,
                                   stringToRender: stringToRender,
                                   localeCode: localeCode,
                                   params: params)
        }
    }
}

/// A static class that is the main point of entry for all the functionality of Transifex Native throughout the SDK.
public final class TXNative : NSObject {
    /// The SDK version
    internal static let version = "0.1.4"
    
    /// The filename of the file that holds the translated strings and it's bundled inside the app.
    public static let STRINGS_FILENAME = "txstrings.json"
    
    /// An instance of the core class that handles all the work
    private static var tx : NativeCore?
    
    /// The available and current locales
    @objc
    public static var locales: TXLocaleState? {
        get {
            tx?.locales
        }
    }

    /// Designated initializer of the TXNative SDK.
    ///
    /// - Parameters:
    ///   - locales: keeps track of the available and current locales
    ///   - token: the Transifex token that can be used for retrieving translations from CDS
    ///   - secret: the Transifex secret that can be used for pushing source strings to CDS
    ///   - cdsHost: the host of the CDS service; defaults to a production CDS service hosted by
    ///   Transifex
    ///   - session: Optional URLSession to be used for all the requests made to the CDS service. If
    ///   no session is provided, an ephemeral URLSession with no cache will be created and used.
    ///   - cache: holds the available translations in various locales. If nil (default) the internal cache
    ///   mechanism will be activated, otherwise the provided cache will be used.
    ///   - missingPolicy: determines how to handle translations that are not available
    ///   - errorPolicy: determines how to handle exceptions when rendering a problematic
    ///   translation (used for ICU rendering strategy)
    ///   - renderingStrategy: determines which strategy to be used when rendering the final
    ///   string; defaults to platform strategy
    @objc
    public static func initialize(
        locales: TXLocaleState,
        token: String,
        secret: String? = nil,
        cdsHost: String? = nil,
        session: URLSession? = nil,
        cache: TXCache? = nil,
        missingPolicy: TXMissingPolicy? = nil,
        errorPolicy: TXErrorPolicy? = nil,
        renderingStrategy: TXRenderingStategy = .platform
    ) {
        guard tx == nil else {
            Logger.warning("Transifex Native is already initialized")
            return
        }
        
        Logger.verbose("""
Initializing TXNative(
locales: \(locales.debugDescription)
token: \(token)
)
""")
        
        tx = NativeCore(locales: locales,
                        token: token,
                        secret: secret,
                        cdsHost: cdsHost,
                        cache: cache,
                        missingPolicy: missingPolicy,
                        errorPolicy: errorPolicy,
                        renderingStrategy: renderingStrategy)
    }
    
    /// Designated initializer of the Transifex SDK using the platform rendering strategy and only the
    /// required fields (locale state and token).
    ///
    /// For a more involved SDK initialization, you can use the
    /// `initialize(locales:token:secret:cdsHost:session:cache:missingPolicy:errorPolicy:renderingStrategy:)`
    /// method.
    ///
    /// - Parameters:
    ///   - locales: keeps track of the available and current locales
    ///   - token: the Transifex token that can be used for retrieving translations from CDS
    @objc
    public static func initialize(
        locales: TXLocaleState,
        token: String
    ) {
        initialize(locales: locales,
                   token: token,
                   secret: nil,
                   cdsHost: nil,
                   session: nil,
                   cache: nil,
                   missingPolicy: nil,
                   errorPolicy: nil,
                   renderingStrategy: .platform)
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
    /// - Parameter tags: An optional list of tags so that only strings that have all of the given tags are fetched.
    /// - Parameter completionHandler: The completion handler that informs the caller with the
    /// new translations and a list of possible errors that might have occured
    @objc
    public static func fetchTranslations(_ localeCode: String? = nil,
                                         tags: [String]? = nil,
                                         completionHandler: TXPullCompletionHandler? = nil) {
        tx?.fetchTranslations(localeCode,
                              completionHandler: completionHandler)
    }
    
    /// Pushes the base translations to CDS.
    ///
    /// - Parameters:
    ///   - translations: A list of `TXSourceString` objects.
    ///   - purge: Whether to replace the entire resource content (true) or not (false). Defaults to false.
    ///   - completionHandler: A callback to be called when the push operation is complete with a
    /// boolean argument that informs the caller that the operation was successful (true) or not (false).
    @objc
    public static func pushTranslations(_ translations: [TXSourceString],
                                        purge: Bool = false,
                                        completionHandler: @escaping (Bool) -> Void) {
        tx?.pushTranslations(translations,
                             purge: purge,
                             completionHandler: completionHandler)
    }
    
    /// Forces CDS cache invalidation.
    ///
    /// - Parameter completionHandler: A callback to be called when force cache invalidation is
    /// complete with a boolean argument that informs the caller that the operation was successful (true) or
    /// not (false).
    @objc
    public static func forceCacheInvalidation(completionHandler: @escaping (Bool) -> Void) {
        tx?.forceCacheInvalidation(completionHandler: completionHandler)
    }
}
