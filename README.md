# Transifex Native iOS SDK

Transifex Native iOS SDK allows fetching translations over the air (OTA) for iOS applications.

## Usage

### SDK configuration
```swift
import UIKit
import TransifexNative

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        TxNative.initialize(
            locales: LocaleState(sourceLocale: "en", appLocales: ["el", "fr"]),
            token: "<transifex_token>",
            secret: "<transifex_secret>",
            cdsHost: "https://cds.svc.transifex.net/",
            cache: MemoryCache(),
            missingPolicy: CompositePolicy(
                PseudoTranslationPolicy(),
                WrappedStringPolicy(start: "[", end: "]")
            )
        )
        TxNative.locales.currentLocale = "el"
        TxNative.fetchTranslations()
        return true
    }
}
```
