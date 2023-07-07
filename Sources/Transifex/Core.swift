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
/// This logic is used when a string for the requested localization is not found and the missing policy
/// is about to be called.
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
    ///   - filterTags: An optional list of tags so that only strings that have all of the given tags are
    ///   fetched.
    ///   - filterStatus: An optional status so that only strings matching translation status are
    ///   fetched.
    init(
        locales: TXLocaleState,
        token: String,
        secret: String?,
        cdsHost: String?,
        cache: TXCache?,
        session: URLSession? = nil,
        missingPolicy: TXMissingPolicy? = nil,
        errorPolicy: TXErrorPolicy? = nil,
        renderingStrategy : TXRenderingStategy,
        filterTags: [String] = [],
        filterStatus: String? = nil
    ) {
        self.locales = locales
        let cdsConfiguration = CDSConfiguration(
            localeCodes: self.locales.appLocales,
            token: token,
            secret: secret,
            cdsHost: cdsHost ?? CDSHandler.CDS_HOST,
            filterTags: filterTags,
            filterStatus: filterStatus
        )
        self.cdsHandler = CDSHandler(
            configuration: cdsConfiguration,
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
    /// - Parameter tags: An optional list of tags so that only strings that have all of the given tags are
    /// fetched.
    /// - Parameter status: An optional status so that only strings matching translation status are
    /// fetched.
    /// - Parameter completionHandler: The completion handler that informs the caller with the
    /// new translations and a list of possible errors that might have occured
    func fetchTranslations(_ localeCode: String? = nil,
                           tags: [String] = [],
                           status: String? = nil,
                           completionHandler: TXPullCompletionHandler? = nil) {
        cdsHandler.fetchTranslations(localeCode: localeCode,
                                     tags: tags,
                                     status: status) { (translations, errors) in
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
    /// boolean argument that informs the caller that the operation was successful (true) or not (false) and
    /// an array that may or may not contain any errors produced during the push operation and an array of
    /// non-blocking errors (warnings) that may have been generated during the push procedure.
    func pushTranslations(_ translations: [TXSourceString],
                          purge: Bool = false,
                          completionHandler: @escaping (Bool, [Error], [Error]) -> Void) {
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
        let localeToRender = localeCode ?? locales.currentLocale
        
        translationTemplate = cache.get(key: sourceString,
                                        localeCode: localeToRender)

        // If the source string cannot be found in the cache, try looking up
        // the generated key for that source string, in case the developer has
        // either used a previous version of the TXCli tool or passed the
        // `hashKeys` argument on the push command.
        if translationTemplate == nil {
            let key = txGenerateKey(sourceString: sourceString,
                                    context: context)

            translationTemplate = cache.get(key: key,
                                            localeCode: localeToRender)
        }
            
        var applyMissingPolicy = false
        
        /// If the string is not found in the cache, use the bypass localizer to look it up on the
        /// application bundle, which returns either the bundled translation if found, or the provided
        /// source string.
        if !String.containsTranslation(translationTemplate) {
            translationTemplate = bypassLocalizer.get(sourceString: sourceString,
                                                      params: params)
        
            /// For source locale, we treat the return value of the bypass localizer as the ground truth
            /// and we use the value to render the final string.
            ///
            /// For target locales, we do the same, with the exception that we pass the final rendered
            /// string from the missing policy to inform the user that this string is missing.
            if !locales.isSource(localeToRender) {
                applyMissingPolicy = true
            }
        }
        
        let renderedString = render(
            sourceString: sourceString,
            stringToRender: translationTemplate,
            localeCode: localeToRender,
            params: params
        )
        
        if applyMissingPolicy {
            return missingPolicy.get(sourceString: renderedString)
        }
        else {
            return renderedString
        }
    }
    
    /// Error string to be rendered when the error policy produces an exception.
    private static let ERROR_FALLBACK = "ERROR"
    
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
            do {
                return try errorPolicy.get(sourceString: sourceString,
                                           stringToRender: stringToRender,
                                           localeCode: localeCode,
                                           params: params)
            }
            catch {
                Logger.error("""
Error running error policy for source string '\(sourceString)' with string to
render '\(stringToRender)' locale code: \(localeCode) params: \(params). Error:
\(error)
""")
                
                return NativeCore.ERROR_FALLBACK
            }
        }
    }
}

/// A static class that is the main point of entry for all the functionality of Transifex Native throughout the SDK.
public final class TXNative : NSObject {
    /// The SDK version
    internal static let version = "1.0.4"
    
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
    /// Do not call initialize() twice without calling dispose() first to deconstruct the previous singleton
    /// instance.
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
    ///   - filterTags: An optional list of tags so that only strings that have all of the given tags are
    ///   fetched.
    ///   - filterStatus: An optional status so that only strings matching translation status are
    ///   fetched.
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
        renderingStrategy: TXRenderingStategy = .platform,
        filterTags: [String]? = nil,
        filterStatus: String? = nil
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
                        session: session,
                        missingPolicy: missingPolicy,
                        errorPolicy: errorPolicy,
                        renderingStrategy: renderingStrategy,
                        filterTags: filterTags ?? [],
                        filterStatus: filterStatus)
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
    
    /// Activate the SDK for a certain Bundle. Use this method to activate the SDK for a Swift package in
    /// case multiple Swift packages are used as modules for an application.
    ///
    /// Only call this method from each module, and not from the main application, by passing the
    /// `Bundle.module` as the argument:
    ///
    /// ```swift
    /// TXNative.activate(bundle: .module)
    /// ```
    ///
    /// Make sure that this method is called after the SDK has been initialized.
    ///
    /// - Parameter bundle: the bundle to be activated. Pass `.bundle` when calling this method
    /// from a Swift package.
    @objc
    public static func activate(bundle: Bundle) {
        guard tx != nil else {
            Logger.error("Transifex Native is not initialized")
            return
        }
        
        Swizzler.activate(bundles: [bundle])
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
    
    /// Helper method used when translation is not possible (e.g. in SwiftUI views).
    ///
    /// This method applies the translation using the currently selected locale. For pluralization use the
    /// `localizedString(format:arguments:)` method.
    ///
    /// Make sure that this method is called after the SDK has been initialized, otherwise
    /// "<SDK NOT INITIALIZED>" string will be shown instead.
    ///
    /// - Parameter sourceString: The source string to be translated
    /// - Returns: The translated string
    public static func t(_ sourceString: String) -> String {
        return tx?.translate(sourceString: sourceString,
                             localeCode: nil,
                             params: [:],
                             context: nil) ?? "<SDK NOT INITIALIZED>"
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
    /// - Parameters:
    ///   - localeCode: If not provided, it will fetch translations for all locales defined in the app
    ///   configuration.
    ///   - tags: An optional list of tags so that only strings that have all of the given tags are fetched.
    ///   - status: An optional status so that only strings matching translation status are fetched.
    ///   - completionHandler: The completion handler that informs the caller when the operation
    ///   is complete, reporting the new translations and a list of possible errors that might have occured.
    @objc
    public static func fetchTranslations(_ localeCode: String? = nil,
                                         tags: [String]? = nil,
                                         status: String? = nil,
                                         completionHandler: TXPullCompletionHandler? = nil) {
        tx?.fetchTranslations(localeCode,
                              tags: tags ?? [],
                              status: status,
                              completionHandler: completionHandler)
    }
    
    /// Pushes the base translations to CDS.
    ///
    /// - Parameters:
    ///   - translations: A list of `TXSourceString` objects.
    ///   - purge: Whether to replace the entire resource content (true) or not (false). Defaults to false.
    ///   - completionHandler: A callback to be called when the push operation is complete with a
    /// boolean argument that informs the caller that the operation was successful (true) or not (false) and
    /// an array that may or may not contain any errors produced during the push operation and an array of
    /// non-blocking errors (warnings) that may have been generated during the push procedure.
    @objc
    public static func pushTranslations(_ translations: [TXSourceString],
                                        purge: Bool = false,
                                        completionHandler: @escaping (Bool, [Error], [Error]) -> Void) {
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
    
    /// Destructs the TXNative singleton instance so that another one can be used.
    @objc
    public static func dispose() {
        tx = nil
    }
}
