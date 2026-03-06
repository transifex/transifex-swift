#import <XCTest/XCTest.h>
#import "TXNativeObjcSwizzler.h"

static NSString *TXExpectedFormatted(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *result = [[NSString alloc] initWithFormat:format
                                                 locale:[NSLocale currentLocale]
                                              arguments:args];
    va_end(args);
    return result;
}

@interface TXNativeObjcSwizzlerTests : XCTestCase

+ (NSString* (^)(NSString *format,
                 NSArray <TXNativeObjcArgument *> *arguments)) closure;

@end

@implementation TXNativeObjcSwizzlerTests

+ (NSString* (^)(NSString *format,
                 NSArray <TXNativeObjcArgument *> *arguments)) closure {
    return ^NSString * (NSString *format,
                        NSArray<TXNativeObjcArgument *> * arguments) {
        NSMutableArray *argumentList = [NSMutableArray new];
        [arguments enumerateObjectsUsingBlock:^(TXNativeObjcArgument *obj,
                                                NSUInteger idx,
                                                BOOL *stop) {
            [argumentList addObject:obj.value ?: @"(null)"];
        }];
        NSString *args = [argumentList componentsJoinedByString:@","];
        return [NSString stringWithFormat:@"format: %@ arguments: %@",
                format,
                args];
    };
}

+ (void)setUp {
    [TXNativeObjcSwizzler swizzleLocalizedStringWithClosure:self.class.closure];
}

+ (void)tearDown {
    [TXNativeObjcSwizzler revertLocalizedString];
}

- (void)testOneInt {
    NSString *finalString = [NSString localizedStringWithFormat:@"Test %d",
                             1];
    NSString *expectedString = @"format: Test %d arguments: 1";

    XCTAssertEqualObjects(finalString, expectedString);
}

- (void)testOneFloatOneString {
    NSString *finalString = [NSString localizedStringWithFormat:@"Test %f %@",
                             3.14, @"Test"];
    NSString *expectedString = @"format: Test %f %@ arguments: 3.14,Test";

    XCTAssertEqualObjects(finalString, expectedString);
}

- (void)testPercentLiteral {
    NSString *finalString = [NSString localizedStringWithFormat:@"Test %% %@",
                             @"ok"];
    NSString *expectedString = @"format: Test %% %@ arguments: ok";

    XCTAssertEqualObjects(finalString, expectedString);
}

- (void)testWidthPrecisionNoStar {
    NSString *finalString = [NSString localizedStringWithFormat:@"Test %08.2f",
                             3.14];
    NSString *expectedString = @"format: Test %08.2f arguments: 3.14";

    XCTAssertEqualObjects(finalString, expectedString);
}

- (void)testCStringInvalidUTF8 {
    const char bytes[] = { (char)0xC3, (char)0x28, 0x00 };
    const char *invalid = bytes;
    NSString *finalString = [NSString localizedStringWithFormat:@"Test %s", invalid];
    NSString *expectedString = @"format: Test %s arguments: (null)";

    XCTAssertEqualObjects(finalString, expectedString);
}

- (void)testRejectsPositionalSpecifiers {
    NSString *actual = [NSString localizedStringWithFormat:@"Test %1$@ %2$@", @"a", @"b"];
    NSString *expected = TXExpectedFormatted(@"Test %1$@ %2$@", @"a", @"b");

    XCTAssertEqualObjects(actual, expected);
}

- (void)testRejectsWidthPrecisionWithStar {
    NSString *actual = [NSString localizedStringWithFormat:@"Test %*.*f", 6, 2, 1.234];
    NSString *expected = TXExpectedFormatted(@"Test %*.*f", 6, 2, 1.234);

    XCTAssertEqualObjects(actual, expected);
}

- (void)testRejectsLengthModifierLL {
    long long value = 42;
    NSString *actual = [NSString localizedStringWithFormat:@"Test %lld", value];
    NSString *expected = TXExpectedFormatted(@"Test %lld", value);

    XCTAssertEqualObjects(actual, expected);
}

- (void)testRejectsLengthModifierZ {
    size_t value = 42;
    NSString *actual = [NSString localizedStringWithFormat:@"Test %zu", value];
    NSString *expected = TXExpectedFormatted(@"Test %zu", value);

    XCTAssertEqualObjects(actual, expected);
}

- (void)testRejectsUnhandledConversionHex {
    int value = 255;
    NSString *actual = [NSString localizedStringWithFormat:@"Test %x", value];
    NSString *expected = TXExpectedFormatted(@"Test %x", value);

    XCTAssertEqualObjects(actual, expected);
}

- (void)testRejectsUnhandledConversionPointer {
    void *ptr = (void *)0x1234;
    NSString *actual = [NSString localizedStringWithFormat:@"Test %p", ptr];
    NSString *expected = TXExpectedFormatted(@"Test %p", ptr);

    XCTAssertEqualObjects(actual, expected);
}

- (void)testRejectsMixedSpecifiers {
    NSString *actual = [NSString localizedStringWithFormat:@"%d %lld", 7, (long long)42];
    NSString *expected = TXExpectedFormatted(@"%d %lld", 7, (long long)42);

    XCTAssertEqualObjects(actual, expected);
}

- (void)testRejectsLongDoubleL {
    long double value = 3.14L;
    NSString *actual = [NSString localizedStringWithFormat:@"Test %Lf", value];
    NSString *expected = TXExpectedFormatted(@"Test %Lf", value);

    XCTAssertEqualObjects(actual, expected);
}

- (void)testRejectsStringsdictPluralSpecifier {
    // %#@varname@ is Apple's stringsdict plural variable specifier.
    // Its argument is a numeric count, not an ObjC object. Reading it as `id`
    // causes ARC to retain an invalid pointer (EXC_BAD_ACCESS). Must fall back.
    NSUInteger count = 1;
    NSString *actual = [NSString localizedStringWithFormat:@"%#@num_images@", count];
    NSString *expected = TXExpectedFormatted(@"%#@num_images@", count);

    XCTAssertEqualObjects(actual, expected);
}

@end
