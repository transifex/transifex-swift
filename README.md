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
                                 appLocales: ["el", "fr"], 
                                 currentLocale: "el"),
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
                                                           currentLocale:@"el"];
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
                        errorPolicy:nil];

    [TxNative fetchTranslations:nil];
    
    return YES;
}
```
