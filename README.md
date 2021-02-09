# Transifex iOS SDK

<p align="left">
<img src="https://img.shields.io/badge/platforms-iOS-lightgrey.svg">
<img src="https://github.com/transifex/transifex-swift/workflows/CI/badge.svg">
</p>

Transifex iOS SDK is a collection of tools to easily localize your iOS applications 
using [Transifex Native](https://www.transifex.com/native/). 

The SDK can fetch translations over the air (OTA), manages an internal cache of translations 
and works seamlessly without requiring any changes in the source code of the app by the 
developer.

Both Objective-C and Swift projects are supported and iOS 10+ is required.

The package is built using Swift 5.3, as it currently requires a bundled resource to be 
present in the package (which was introduced on version 5.3). An update that will require 
a lower Swift version is currently WIP.

Learn more about [Transifex Native](https://docs.transifex.com/transifex-native-sdk-overview/introduction).

The full documentation is available at [https://transifex.github.io/transifex-swift/](https://transifex.github.io/transifex-swift/).

## Minimum Requirements

| Swift           | Xcode           | Platforms                                         |
|-----------------|-----------------|---------------------------------------------------|
| Swift 5.3       | Xcode 12.3      | iOS 10.0  |

## Usage

The SDK allows you to keep using the same localization hooks that the iOS framework 
provides, such as `NSLocalizedString`, 
`String.localizedStringWithFormat(format:...)`, etc, while at the same time taking 
advantage of the features that Transifex Native offers, such as OTA translations.

Below you can find examples of the SDK initialization both in Swift and Objective-C for
an app that uses the English language (`en`) as its source locale and it's localized both in
Greek (`el`) and French (`fr`). 

Keep in mind that in the sample code below you will have to replace 
`<transifex_token>` and `<transifex_secret>` with the actual token and secret that 
are associated with your Transifex project and resource. 

### SDK configuration (Swift)

```swift
import Transifex

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        TXNative.initialize(
            locales: TXLocaleState(sourceLocale: "en", 
                                   appLocales: ["en", "el", "fr"]),
            token: "<transifex_token>",
            secret: "<transifex_secret>",
            missingPolicy: TXCompositePolicy(
                TXPseudoTranslationPolicy(),
                TXWrappedStringPolicy(start: "[", end: "]")
            )
        )
        
        /// Optional: Fetch translations on launch
        TXNative.fetchTranslations()
        return true
    }
}
```

For Swift projects, you  will also need to copy the `TXNativeExtensions.swift` file in 
your project and include it in all of the targets that call any of the following Swift methods:

* `String.localizedStringWithFormat(format:...)`
* `NSString.localizedStringWithFormat(format:...)`

If none of your application targets call any of the above methods, then you don't need to
add this file to your project.

### SDK configuration (Objective-C)

```objc
@import Transifex;

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    TXLocaleState *localeState = [[TXLocaleState alloc] initWithSourceLocale:@"en"
                                                                  appLocales:@[
                                                                    @"en",
                                                                    @"el",
                                                                    @"fr"
                                                                  ]
                                                       currentLocaleProvider:nil];
    TXPseudoTranslationPolicy *pseudoTranslationPolicy = [TXPseudoTranslationPolicy new];
    TXWrappedStringPolicy *wrappedStringPolicy = [[TXWrappedStringPolicy alloc] initWithStart:@"["
                                                                                          end:@"]"];
    TXCompositePolicy *compositePolicy = [[TXCompositePolicy alloc] init:@[
        pseudoTranslationPolicy,
        wrappedStringPolicy
    ]];

    [TXNative initializeWithLocales:localeState
                              token:@"<transifex_token>"
                             secret:@"<transifex_secret>"
                            cdsHost:nil
                            session:nil
                              cache:nil
                      missingPolicy:compositePolicy
                        errorPolicy:nil
                  renderingStrategy:TXRenderingStategyPlatform
                             logger:nil];
                             
    /// Optional: Fetch translations on launch
    [TXNative fetchTranslations:nil
              completionHandler:nil];
    
    return YES;
}
```

### Alternative initialization

If you want your application to make use of the default behavior, you can initialize the 
SDK using a simpler initilization method:

#### Swift

```swift
TXNative.initialize(
    locales: localeState,
    token: "<transifex_token>"
)
```
#### Objective-C

```objc
[TXNative initializeWithLocales:localeState
                          token:@"<transifex_token>"];
```

### Fetching translations

As soon as `fetchTranslations` is called, the SDK will attempt to download the 
translations for all locales - except for the source locale - that are defined in the 
initialization of `TXNative`. 

The `fetchTranslations` method in the above examples is called as soon as the
application launches, but that's not required. Depending on the application, the developer
might choose to call that method whenever it is most appropriate (for example, each time
the application is brought to the foreground or when the internet connectivity is 
established).

### Pushing source content

In order to push the source translations to CDS, you will first need to prepare an array of 
`TXSourceString` objects that will hold all the necessary information needed for CDS. 
You can refer to the `TXSourceString` class for more information, or you can look at the 
list below:

* `key` (required): The key of the source string, generated via the public `txGenerateKey()` 
method.
* `sourceString` (required): The actual source string.
* `developerComment` (optional): An optional comment provided by the developer to
assist the translators.
* `occurrencies` (required): A list of relative paths where the source string is located in 
the project.
* `tags` (optional): An optional list of tags that will appear alongside the source string in
the Transifex dashboard.
* `characterLimit` (requred): Source string limit that should be respected by translators.
* `context` (optional): An optional list of strings that provide more context.

After building an array of `TXSourceString` objects, use the `pushTranslations` method 
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
`Transifex` library in the 'Frameworks and Libraries' section of the General 
settings of the application extension you are working on.

Furthermore, in case Xcode produces a "No such module 'Transifex'" error on the 
`import Transifex` statements of the extension files, be sure to add the 
`$(SRCROOT)` path in the 'Framework Search Paths' setting under the Build Settings of the 
application extension target.

In order to make the Transifex SDK cache file visible by both the extension and the main 
application targets, you would need to enable the App Groups capability in both the main 
application and the extension targets and use an existing or create a new app group 
identifier. Then, you would need to initialize the Transifex SDK with the `TXStandardCache` 
passing that app group identifier as the `groupIdentifier` argument.

### URL Session

By default, an ephemeral URLSession object with no cache is used for all requests made 
to the CDS service.

For more control over the networking layer, an optional `session` parameter is exposed in 
the `initialize()` method of the `TXNative` cache, so that developers can offer their
own session object, if that's desirable (e.g. for more fine grained cache control, certificate
pinning etc).

### Logging

By default, warning and error messages produced by the SDK are logged in the console 
using the `print()` method. Developers can offer a class that conforms to the `TXLogger`
protocol so that they can control the logging mechanism of the SDK or make use of the
public `TXStandardLogHandler` class to control the log level printed to the console.

## Limitations

### Special cases

Localized strings that are being managed by the OS are not supported by the Transifex 
SDK:

* Localized entries found in the  `Info.plist` file (e.g. Bundle Display Name and Usage 
Description strings) that are included in the `InfoPList.strings` file.
* Localized entried found in the `Root.plist` of the `Settings.bundle` of an app that
exposes its Settings to the iOS Settings app that are included in the `Root.strings` file.

### ICU support

Also, currently SDK supports only supports the platform rendering strategy, so if the ICU
rendering strategy is passed during the initialization, translations will trigger the error 
policy.

### Internet connectivity

If the device cannot access the Internet when `fetchTranslations()` method is called,
the internal logic of the SDK doesn't retry or wait for a connection, in order to preserve
resources. Developers are free to detect when internet connectivity is regained in order to
re-call that method.

## Sample applications

You can find two [sample applications](https://github.com/transifex/transifex-native-sandbox/tree/master/ios) that make use of the Transifex iOS SDK, in Swift and Objective-C.

## Documentation

The [documentation of this SDK](https://transifex.github.io/transifex-swift/) has been 
generated using [Jazzy](https://github.com/realm/jazzy) using the following command:

```
jazzy -g https://github.com/transifex/transifex-swift/ -m Transifex
```

## License
Licensed under Apache License 2.0, see [LICENSE](LICENSE) file.
