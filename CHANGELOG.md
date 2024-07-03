# Transifex iOS SDK

## Transifex iOS SDK 0.1.0

*February 4, 2021*

- Public release

## Transifex iOS SDK 0.1.1

*February 24, 2021*

- Fixed preferred locale provider

## Transifex iOS SDK 0.1.2

*March 17, 2021*

- Applies minor refactors in cache logic
- Renames override policy to update policy and improves documentation.

## Transifex iOS SDK 0.1.3

*March 22, 2021*

- Fixes a minor version issue

## Transifex iOS SDK 0.1.4

*March 24, 2021*

- Exposes `TXStandardCache.getCache` method in Objective-C.

## Transifex iOS SDK 0.5.0

*June 25, 2021*

- Allows pull command to fetch source string content.
- Introduces public `dispose()` method to destruct the `TXNative` singleton instance.
- Adds tag filter support when fetching translations via the `fetchTranslations` method.
- Exposes `TXSourceString` read-only properties.

## Transifex iOS SDK 0.5.1

*July 12, 2021*

- Improves error policy behavior.

## Transifex iOS SDK 1.0.0

*July 28, 2021*

- Updates endpoint logic for v2 of CDS.
- Push translations method now also returns an array of errors.
- Improves CDSHandler unit tests.

## Transifex iOS SDK 1.0.1

*September 22, 2021*

- When rendering a translation the logic now first uses the original source 
string as a key to look up to the cache and falls back to the generated hash
key if the entry is not found.

## Transifex iOS SDK 1.0.2

*November 28, 2022*

- Adds method to activate SDK from a Swift Package.
- Adds reference to SwiftUI limitation in README.

## Transifex iOS SDK 1.0.3

*December 27, 2022*

- Fixes TXPreferredLocaleProvider so that it uses the correct language candidate
based on user's preference and supported languages by the app developer.
- Fixes deprecation warnings on Github action.

## Transifex iOS SDK 1.0.4

*February 10, 2023*

- Improves tags filter support.
- Adds status filter support.
- Tags and status filters can be either specified during initialization and/or
when `fetchTranslations()` is called.
- Fixes issue where the passed custom session was not being used.

## Transifex iOS SDK 2.0.0

*July 7, 2023*

- Adds `t()` translation method for cases where Transifex iOS logic cannot
intercept the localization (e.g. SwiftUI).
- `pushTranslations()` now reports back any generated warnings as a separate
array.
- Push logic detects and reports warnings such as duplicate source string keys
or empty source string keys.
- `pushTranslations()` now accepts a configuration object that holds any extra
options that might need to be set during the push logic.

## Transifex iOS SDK 2.0.1

*September 21, 2023*

- Addresses language tag discrepancy: The fallback mechanism for accessing the
bundled source locale translations, in case the target translations was not
found, was trying to access the file by using the format that Transifex uses
(e.g. `en_US`) instead of the one that iOS and Xcode use (e.g. `en-US`). The
logic now normalizes the locale name to match the format that iOS accepts.

## Transifex iOS SDK 2.0.2

*May 29, 2024*

- Adds full support for String Catalogs support.
- Adds support for substitution phrases on old Strings Dictionary file format.
- Updates unit tests.

## Transifex iOS SDK 2.0.3

*June 3, 2024*

- Adds SwiftUI support via attributed string swizzling.

## Transifex iOS SDK 2.0.4

*June 21, 2024*

- Updates minimum supported OS versions.

## Transifex iOS SDK 2.0.5

*July 3, 2024*

* Ensures that callbacks won't capture `self` strongly.
* Ensures Designed for iPhone/iPad apps use the proper device name.
* Discloses that completion handlers are called from background threads.
* Improves cache update after a `fetchTranslations` call.
