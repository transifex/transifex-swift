//
//  TXNativeObjcSwizzlerTests.m
//  TransifexNative
//
//  Created by Stelios Petrakis on 16/11/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

#import <XCTest/XCTest.h>
#import "TXNativeObjcSwizzler.h"

@interface TXNativeObjcSwizzlerTests : XCTestCase

@end

@implementation TXNativeObjcSwizzlerTests

- (void)setUp {
    [TXNativeObjcSwizzler activateWithClosure:^NSString * (NSString *format,
                                                           NSArray<TXNativeObjcArgument *> *arguments) {
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
    }];
}

- (void)testOneInt {
    NSString *finalString = [NSString localizedStringWithFormat:@"Test %d",
                             1];
    NSString *expectedString = @"format: Test %d arguments: 1";
    
    XCTAssertTrue([finalString isEqualToString:expectedString]);
}

- (void)testOneFloatOneString {
    NSString *finalString = [NSString localizedStringWithFormat:@"Test %f %@",
                             3.14, @"Test"];
    NSString *expectedString = @"format: Test %f %@ arguments: 3.14,Test";
    
    XCTAssertTrue([finalString isEqualToString:expectedString]);
}

@end
