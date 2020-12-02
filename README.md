# Transifex Native iOS SDK

Transifex Native iOS SDK is a collection of tools to easily localize your iOS applications using [Transifex Native](https://www.transifex.com/native/). The can fetch translations over the air (OTA) to your apps. It supports apps built both on Objective-C and Swift.

The package is built using Swift 5.3, as it currently requires a bundled resource to be present in the package (which was introduced on version 5.3). An update that will require a lower Swift version is currently WIP.

Learn more about [Transifex Native](https://docs.transifex.com/transifex-native-sdk-overview/introduction).

## Usage

The SDK allows you to keep using the same localization hooks that the iOS framework provides, such as 
`NSLocalizedString`, `String.localizedStringWithFormat(format:...)`, etc, but at the same time 
taking advantage of the features that Transifex Native offers, such as OTA translations.

Keep in mind that in the sample code below you will have to replace `<transifex_token>` and `<transifex_secret>` 
with the actual token and secret that are associated with your Transifex project and resource. 

### SDK configuration (Swift)

```swift
import TransifexNative

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        TxNative.initialize(
            locales: LocaleState(sourceLocale: "en", 
                                 appLocales: ["el", "fr"]),
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
                                                                  @"el" ,
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
As soon as `fetchTranslations` is called, the SDK will attempt to download the translations for all locales
that are defined in the initialization of `TxNative`. 

For the moment, the translations are stored only in memory and are available for the current app session.
In later versions of the SDK, the translations will also be stored on the device and will be available for subsequent
app sessions.

### Pushing source content
In order to push the source translations to CDS, you will first need to prepare an array of `TxSourceString` objects
that will hold all the necessary information needed for CDS. You can refer to the `TxSourceString` class for more
information, or you can look at the list below:

* `key` (required): The key of the source string, generated via the public `generateKey()` method.
* `sourceString` (required): The actual source string.
* `developerComment` (optional): An optional comment provided by the developer to assist the translators.
* `occurrencies` (required): A list of relative paths where the source string is located in the project.

After building an array of `TxSourceString` objects, use the `pushTranslations` method to push them to CDS. You can optionally set the `purge` argument to `true` (defaults to `false`) to replace the entire resource content. The completion handler can be used to get notified asynchronously whether the request was successful or not.

### Invalidating CDS cache
The cache of CDS has a TTL of 30 minutes. If you update some translations on Transifex and you need
to see them on your app immediately, you need to make an HTTP request to the [invalidation endpoint](https://github.com/transifex/transifex-delivery/#invalidate-cache) of CDS.

## License
Licensed under Apache License 2.0, see [LICENSE](LICENSE) file.
