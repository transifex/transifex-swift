//
//  TXNativeObjcSwizzlerTests.m
//  Transifex
//
//  Created by Stelios Petrakis on 16/11/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "TXNativeObjcSwizzler.h"
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

@interface TXNativeObjcSwizzlerTests : XCTestCase

+ (NSString* (^)(NSString *format, NSArray <TXNativeObjcArgument *> *arguments)) closure;

@end

@implementation TXNativeObjcSwizzlerTests

+ (NSString* (^)(NSString *format, NSArray <TXNativeObjcArgument *> *arguments)) closure {
    return ^NSString * (NSString *format,
                        NSArray<TXNativeObjcArgument *> * arguments) {
        NSMutableArray *argumentList = [NSMutableArray new];
        [arguments enumerateObjectsUsingBlock:^(TXNativeObjcArgument *obj,
                                                NSUInteger idx,
                                                BOOL *stop) {
            [argumentList addObject:obj.value];
        }];
        NSString *args = [argumentList componentsJoinedByString:@","];
        return [NSString stringWithFormat:@"format: %@ arguments: %@",
                format,
                args];
    };
}

- (void)testOneInt {
    [TXNativeObjcSwizzler swizzleLocalizedStringWithClosure:self.class.closure];

    NSString *finalString = [NSString localizedStringWithFormat:@"Test %d",
                             1];
    NSString *expectedString = @"format: Test %d arguments: 1";

    XCTAssertEqualObjects(finalString, expectedString);

    [TXNativeObjcSwizzler revertLocalizedString];
}

- (void)testOneFloatOneString {
    [TXNativeObjcSwizzler swizzleLocalizedStringWithClosure:self.class.closure];

    NSString *finalString = [NSString localizedStringWithFormat:@"Test %f %@",
                             3.14, @"Test"];
    NSString *expectedString = @"format: Test %f %@ arguments: 3.14,Test";

    XCTAssertEqualObjects(finalString, expectedString);

    [TXNativeObjcSwizzler revertLocalizedString];
}

- (void)testAttributed API_AVAILABLE(macos(12.0)) {
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

    [TXNative initializeWithLocales:localeState
                              token:@"<token>"
                             secret:nil
                            cdsHost:nil
                            session:nil
                              cache:memoryCache
                      missingPolicy:nil
                        errorPolicy:nil
                  renderingStrategy:TXRenderingStategyPlatform
                         filterTags:nil
                       filterStatus:nil];

    NSString *string = [NSBundle.mainBundle localizedAttributedStringForKey:@"a"
                                                                      value:nil
                                                                      table:nil].string;
    XCTAssertEqualObjects(string, @"α");

    [TXNative dispose];
}

@end
