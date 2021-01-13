# Transifex Native iOS SDK

Transifex Native iOS SDK is a collection of tools to easily localize your iOS applications 
using [Transifex Native](https://www.transifex.com/native/). The tool can fetch translations 
over the air (OTA) to your apps. It supports apps built both on Objective-C and Swift.

The package is built using Swift 5.3, as it currently requires a bundled resource to be 
present in the package (which was introduced on version 5.3). An update that will require 
a lower Swift version is currently WIP.

Learn more about [Transifex Native](https://docs.transifex.com/transifex-native-sdk-overview/introduction).

## Usage

The SDK allows you to keep using the same localization hooks that the iOS framework 
provides, such as `NSLocalizedString`, 
`String.localizedStringWithFormat(format:...)`, etc, but at the same time taking 
advantage of the features that Transifex Native offers, such as OTA translations.

Keep in mind that in the sample code below you will have to replace 
`<transifex_token>` and `<transifex_secret>` with the actual token and secret that 
are associated with your Transifex project and resource. 

### SDK configuration (Swift)

```swift
import TransifexNative

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        TxNative.initialize(
            locales: LocaleState(sourceLocale: "en", 
                                 appLocales: ["en", "el", "fr"]),
            token: "<transifex_token>",
            secret: "<transifex_secret>",
            cdsHost: "https://cds.svc.transifex.net/",
            cache: MemoryCache(),
            missingPolicy: CompositePolicy(
                PseudoTranslationPolicy(),
                WrappedStringPolicy(start: "[", end: "]")
            )
        )
        TxNative.fetchTranslations()
        return true
    }
}
```

You  also need to copy the `TXExtensions.swift` file in your project and include it in all 
of the targets that call any of the following methods:

* `String.localizedStringWithFormat(format:...)`
* `NSString.localizedStringWithFormat(format:...)`

If none of your application targets call any of the above methods, then you don't need to
add this file to your project.

### SDK configuration (Objective-C)

```objc
@import TransifexNative;

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    LocaleState *localeState = [[LocaleState alloc] initWithSourceLocale:@"en"
                                                              appLocales:@[
                                                                  @"en",
                                                                  @"el",
                                                                  @"fr"
                                                              ]
                                                   currentLocaleProvider:nil];
    PseudoTranslationPolicy *pseudoTranslationPolicy = [PseudoTranslationPolicy new];
    WrappedStringPolicy *wrappedStringPolicy = [[WrappedStringPolicy alloc] initWithStart:@"["
                                                                                      end:@"]"];
    CompositePolicy *compositePolicy = [[CompositePolicy alloc] init:@[
        pseudoTranslationPolicy,
        wrappedStringPolicy
    ]];

    [TxNative initializeWithLocales:localeState
                              token:@"<transifex_token>"
                             secret:@"<transifex_secret>"
                            cdsHost:@"https://cds.svc.transifex.net/"
                              cache:[MemoryCache new]
                      missingPolicy:compositePolicy
                        errorPolicy:nil
                  renderingStrategy:RenderingStategyPlatform];

    [TxNative fetchTranslations:nil];
    
    return YES;
}
```

### Fetching translations

As soon as `fetchTranslations` is called, the SDK will attempt to download the 
translations for all locales - except for the source locale - that are defined in the 
initialization of `TxNative`. 

For the moment, the translations are stored only in memory and are available for the 
current app session. In later versions of the SDK, the translations will also be stored on 
the device and will be available for subsequent app sessions.

### Pushing source content

In order to push the source translations to CDS, you will first need to prepare an array of 
`TxSourceString` objects that will hold all the necessary information needed for CDS. 
You can refer to the `TxSourceString` class for more information, or you can look at the 
list below:

* `key` (required): The key of the source string, generated via the public `generateKey()` 
method.
* `sourceString` (required): The actual source string.
* `developerComment` (optional): An optional comment provided by the developer to
assist the translators.
* `occurrencies` (required): A list of relative paths where the source string is located in 
the project.

After building an array of `TxSourceString` objects, use the `pushTranslations` method 
to push them to CDS. You can optionally set the `purge` argument to `true` (defaults to 
`false`) to replace the entire resource content. The completion handler can be used to 
get notified asynchronously whether the request was successful or not.

### Standard Cache

The default cache strategy used by the SDK, if no other cache is provided by the 
developer, is the `TXStandardCache`. The standard cache operates by making use of the 
publicly exposed classes and protocols from the Cache.swift file of the SDK, so it's easy 
to construct another cache strategy if that's desired.

The standard cache is initialized with a memory cache (`TXMemoryCache`) that manages all 
cached entries in memory. After the memory cache gets initialized, it tries to look up if 
there are any already stored cache files in the file system using the 
`TXDiskCacheProvider` class: 

* The first cache provider is the bundle cache provider, that looks up for an already 
created cache file in the main application bundle of the app that may have been offered 
by the developer.
* The second cache provider looks up for a cache file in the application sandbox directory 
(using the optional app group identifier argument if provided), in case the app had  already 
downloaded the translations from the server from a previous launch.

Those two providers are used to initialize the memory cache using an override policy 
(`TXCacheOverridePolicy`) which is optionally provided by the developer and defaults to 
the `overrideAll` value. 

After the cached entries have updated the memory cache, the cache is ready to be used.

Whenever new translations are fetched from the server using the `fetchTranslations()` 
method, the standard cache is updated and those translations are stored as-is in the file 
system, in the same cache file used by the aforementioned second cache provider so that 
they are available on the next app launch.

#### Alternative cache strategy

You might want to update the internal memory cache as soon as the newly downloaded 
translations are available and always override all entries, so that the override policy can 
also be ommited. 

In order to achieve that, you can create a new  `TXDecoratorCache` subclass that has a 
similar initializer as the `TXStandardCache` one, with the exception of the 
`TXReadonlyCacheDecorator` and the `TXStringOverrideFilterCache` initializers:
 
 ```swift
 public init(groupIdentifier: String? = nil) {
     // ...Same as TXStandardCache...

     let cache = TXFileOutputCacheDecorator(
         fileURL: downloadURL,
         internalCache: TXProviderBasedCache(
             providers: providers,
             internalCache: TXMemoryCache()
         )
     )
     
     super.init(internalCache: cache)
 }
 ```
 
 This way, whenever the cache is updated with the new translations from the 
 `fetchTranslations()` method, the `update()` call will propagate to the internal
 `TXMemoryCache` and update all of its entries.
 
### Application Extensions

In order to add the SDK to an application extension target, be sure to include the 
`TransifexNative` library in the 'Frameworks and Libraries' section of the General 
settings of the application extension you are working on.

Furthermore, in case Xcode produces a "No such module 'TransifexNative'" error on the 
`import TransifexNative` statements of the extension files, be sure to add the 
`$(SRCROOT)` path in the 'Framework Search Paths' setting under the Build Settings of the 
application extension target.

In order to make the Transifex Native SDK cache file visible by both the extension and the 
main application targets, you would need to enable the App Groups capability in both the 
main application and the extension targets and use an existing or create a new app group 
identifier. Then, you would need to initialize the Transifex Native SDK with the 
`TXStandardCache` passing that app group identifier as the `groupIdentifier` argument.

### Invalidating CDS cache

The cache of CDS has a TTL of 30 minutes. If you update some translations on Transifex 
and you need to see them on your app immediately, you need to make an HTTP request 
to the [invalidation endpoint](https://github.com/transifex/transifex-delivery/#invalidate-cache) 
of CDS.

## License
Licensed under Apache License 2.0, see [LICENSE](LICENSE) file.
