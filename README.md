# Transifex Native iOS SDK

Transifex Native iOS SDK allows fetching translations over the air (OTA) for iOS applications.

## Usage

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

If none of your application target's call any of the above methods, then you don't need to
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
                              token:@"token"
                             secret:@"secret"
                            cdsHost:@"https://cds.svc.transifex.net/"
                              cache:[MemoryCache new]
                      missingPolicy:compositePolicy
                        errorPolicy:nil
                  renderingStrategy:RenderingStategyPlatform];

    [TxNative fetchTranslations:nil];
    
    return YES;
}
```
