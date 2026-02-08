//
//  TXNativeObjcTests.m
//  Transifex
//
//  Created by Stelios Petrakis on 16/11/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

#import <XCTest/XCTest.h>
@import Transifex;

@interface MockLocaleProvider : NSObject <TXCurrentLocaleProvider>

@property (nonatomic) NSString *mockLocaleCode;

@end

@implementation MockLocaleProvider

- (instancetype)initWithMockLocaleCode:(NSString *)localeCode {
    if (self = [super init]) {
        self.mockLocaleCode = localeCode;
    }

    return self;
}

- (NSString *)currentLocale {
    return self.mockLocaleCode;
}

@end

@interface TXNativeObjcTests : XCTestCase

@end

@implementation TXNativeObjcTests

- (void)testAttributed API_AVAILABLE(macos(12.0), ios(15.0), watchos(8.0), tvos(15.0)) {
    TXMemoryCache *memoryCache = [TXMemoryCache new];
    [memoryCache updateWithTranslations:@{
        @"en": @{
            @"a": @{ @"string": @"a" }
        },
        @"el": @{
            @"a": @{ @"string": @"α" }
        },
    }];

    MockLocaleProvider *mockLocaleProvider = [MockLocaleProvider.alloc initWithMockLocaleCode:@"el"];

    TXLocaleState *localeState = [TXLocaleState.alloc initWithSourceLocale:@"en"
                                                                appLocales:@[ @"el" ]
                                                     currentLocaleProvider:mockLocaleProvider];

    [[[[TXNativeBuilder.new
        setLocales:localeState]
        setToken:@"<token>"]
        setCache:memoryCache]
        build];

    NSString *string = [NSBundle.mainBundle localizedAttributedStringForKey:@"a"
                                                                      value:nil
                                                                      table:nil].string;
    XCTAssertEqualObjects(string, @"α");

    [TXNative dispose];
}

- (void)testBuilder {
    MockLocaleProvider *mockLocaleProvider = [MockLocaleProvider.alloc initWithMockLocaleCode:@"el"];
    TXLocaleState *locales = [TXLocaleState.alloc initWithSourceLocale:@"en"
                                                            appLocales:@[ @"el" ]
                                                 currentLocaleProvider:mockLocaleProvider];

    XCTAssertFalse([TXNativeBuilder.new build]);

    XCTAssertFalse([[TXNativeBuilder.new
                     setToken:@"token"]
                     build]);

    XCTAssertFalse([[TXNativeBuilder.new
                     setLocales:locales]
                     build]);

    XCTAssertTrue([[[TXNativeBuilder.new
                     setLocales:locales]
                     setToken:@"token"]
                     build]);

    [TXNative dispose];
}

@end
