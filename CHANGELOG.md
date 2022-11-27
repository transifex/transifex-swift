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
