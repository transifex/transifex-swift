//
//  TXNativeObjcSwizzler.m
//  Transifex
//
//  Created by Stelios Petrakis on 5/11/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

#import <objc/runtime.h>
#import "TXNativeObjcSwizzler.h"

static NSString *(^TXNativeObjcSwizzlerClosure)(NSString *, NSArray <id> *);

@implementation NSString (TXNativeObjcSwizzler)

+ (instancetype)swizzledLocalizedStringWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2) {
    va_list argumentList;
    va_start(argumentList, format);
    va_list originalArgs;
    va_copy(originalArgs, argumentList);

    // Strictly match conversion specs like: %[flags][width][.precision][length]conv
    NSString *regExPattern = @"%(%|(?:[#+\\-0 ]*)(?:\\d+)?(?:\\.\\d+)?(?:hh|h|ll|l|j|z|t|L)?[@aAcCdDeEfFgGiIoOsSpuxX])";
    NSRegularExpression *regex = [NSRegularExpression
                                  regularExpressionWithPattern:regExPattern
                                  options:0
                                  error:nil];

    if (!regex) {
        NSString *original =
            [self tx_originalLocalizedStringWithFormat:format
                                                vaList:originalArgs];
        va_end(originalArgs);
        va_end(argumentList);
        return original;
    }

    NSArray<NSTextCheckingResult *> *matches =
        [regex matchesInString:format
                       options:0
                         range:NSMakeRange(0, format.length)];

    // Sanity check: Ensure all % tokens are matched by the regex.
    NSInteger percentCount = 0;
    for (NSUInteger i = 0; i < format.length; i++) {
        if ([format characterAtIndex:i] != '%') {
            continue;
        }
        percentCount++;
        if (i + 1 < format.length
            && [format characterAtIndex:i + 1] == '%') { // skip second '%'
            i++;
        }
    }

    if (percentCount != matches.count) {
        NSString *original =
            [self tx_originalLocalizedStringWithFormat:format
                                                vaList:originalArgs];
        va_end(originalArgs);
        va_end(argumentList);
        return original;
    }

    NSMutableArray <TXNativeObjcArgument *> *arguments = [NSMutableArray new];
    BOOL shouldFallback = NO;

    for (NSTextCheckingResult *match in matches) {
        NSString *originalMatchString = [format substringWithRange:match.range];

        // Reject positional arguments and width/precision star.
        if ([originalMatchString rangeOfString:@"$"].location != NSNotFound ||
            [originalMatchString rangeOfString:@"*"].location != NSNotFound) {
            shouldFallback = YES;
            break;
        }

        // Extract the conversion character (last char)
        unichar conv =
            [originalMatchString characterAtIndex:originalMatchString.length - 1];

        TXNativeObjcArgument *arg = [TXNativeObjcArgument new];

        switch (conv) {
            // Integer (%d, %i)
            case 'd': case 'i': {
                // Reject length modifiers
                if ([NSString tx_containsLengthModifier:originalMatchString]) {
                    shouldFallback = YES;
                    break;
                }
                int intObject = va_arg(argumentList, int);
                arg.value = @(intObject);
                arg.type = TXNativeObjcArgumentTypeInt;
                break;
            }
            // Unsigned (%u)
            case 'u': {
                // Reject length modifiers
                if ([NSString tx_containsLengthModifier:originalMatchString]) {
                    shouldFallback = YES;
                    break;
                }
                unsigned unsignedObject = va_arg(argumentList, unsigned);
                arg.value = @(unsignedObject);
                arg.type = TXNativeObjcArgumentTypeUnsigned;
                break;
            }
            // Double (%e, %E, %g, %G, %a, %A, %f, %F)
            case 'e': case 'E':
            case 'g': case 'G':
            case 'a': case 'A':
            case 'f': case 'F': {
                // Only fall back for L (long double)
                if ([originalMatchString rangeOfString:@"L"].location != NSNotFound) {
                    shouldFallback = YES;
                    break;
                }
                double doubleObject = va_arg(argumentList, double);
                arg.value = @(doubleObject);
                arg.type = TXNativeObjcArgumentTypeDouble;
                break;
            }
            // Character (%c)
            case 'c': {
                int charObject = va_arg(argumentList, int);
                arg.value = [NSString stringWithFormat:@"%c", charObject];
                arg.type = TXNativeObjcArgumentTypeChar;
                break;
            }
            // C String (%s)
            case 's': {
                char *charObject = va_arg(argumentList, char *);
                if (!charObject) {
                    arg.value = @"(null)";
                }
                else {
                    arg.value = [NSString stringWithUTF8String:charObject];
                }
                arg.type = TXNativeObjcArgumentTypeCString;
                break;
            }
            // Objective-C object (%@)
            case '@': {
                // %#@ is Apple's stringsdict plural variable specifier so its
                // argument is a numeric count, not an ObjC object pointer.
                // Reading it as `id` causes ARC to retain an invalid pointer,
                // resulting in EXC_BAD_ACCESS. Fall back for any %#@ match.
                if ([originalMatchString rangeOfString:@"#"].location != NSNotFound) {
                    shouldFallback = YES;
                    break;
                }
                id obj = va_arg(argumentList, id);
                arg.value = obj;
                arg.type = TXNativeObjcArgumentTypeObject;
                break;
            }
            // '%' character (%%)
            case '%': {
                // Percent literal has no argument to pass through.
                continue;
            }
            default:
                shouldFallback = YES;
                break;
        }

        if (shouldFallback) {
            break;
        }

        [arguments addObject:arg];
    }

    // Perform a local-capture of the closure to avoid race conditions.
    NSString *(^closure)(NSString *, NSArray<id> *) = TXNativeObjcSwizzlerClosure;

    if (shouldFallback || closure == nil) {
        NSString *original =
            [self tx_originalLocalizedStringWithFormat:format
                                                vaList:originalArgs];
        va_end(originalArgs);
        va_end(argumentList);
        return original;
    }

    va_end(originalArgs);
    va_end(argumentList);
    return closure(format,
                   arguments);
}

/// Returns the original Foundation formatting result for a format string and va_list.
/// This bypasses swizzled parsing/translation and avoids variadic swizzle recursion.
/// Safe to use as a fallback when we cannot parse the format specifiers reliably.
+ (instancetype)tx_originalLocalizedStringWithFormat:(NSString *)format
                                              vaList:(va_list)args {
    va_list argsCopy;
    va_copy(argsCopy, args);

    NSString *result = [[NSString alloc] initWithFormat:format
                                                 locale:NSLocale.currentLocale
                                              arguments:argsCopy];

    va_end(argsCopy);
    return result;
}

#pragma mark - Helper

/// Returns YES if the format specifier string contains a length modifier that changes the integer argument
/// type away from plain int/unsigned int (i.e. h, hh, l, ll, j, z, t).
+ (BOOL)tx_containsLengthModifier:(NSString *)specifier {
    return [specifier rangeOfString:@"h"].location != NSNotFound ||
           [specifier rangeOfString:@"l"].location != NSNotFound ||
           [specifier rangeOfString:@"j"].location != NSNotFound ||
           [specifier rangeOfString:@"z"].location != NSNotFound ||
           [specifier rangeOfString:@"t"].location != NSNotFound;
}

@end

@implementation TXNativeObjcArgument

@end

@implementation TXNativeObjcSwizzler

+ (void)swizzleLocalizedStringWithClosure:(NSString* (^)(NSString *format,
                                                         NSArray <TXNativeObjcArgument *> *arguments))closure {
    TXNativeObjcSwizzlerClosure = closure;

    Method m1 = class_getClassMethod(NSString.class, @selector(localizedStringWithFormat:));
    Method m2 = class_getClassMethod(NSString.class, @selector(swizzledLocalizedStringWithFormat:));
    method_exchangeImplementations(m1, m2);
}

+ (void)revertLocalizedString {
    TXNativeObjcSwizzlerClosure = nil;

    Method m1 = class_getClassMethod(NSString.class, @selector(localizedStringWithFormat:));
    Method m2 = class_getClassMethod(NSString.class, @selector(swizzledLocalizedStringWithFormat:));
    method_exchangeImplementations(m2, m1);
}

+ (void)swizzleLocalizedAttributedString:(Class)class selector:(SEL)selector {
    Method m1 = class_getInstanceMethod(NSBundle.class, @selector(localizedAttributedStringForKey:value:table:));
    Method m2 = class_getInstanceMethod(class, selector);
    method_exchangeImplementations(m1, m2);
}

+ (void)revertLocalizedAttributedString:(Class)class selector:(SEL)selector {
    Method m1 = class_getInstanceMethod(NSBundle.class, @selector(localizedAttributedStringForKey:value:table:));
    Method m2 = class_getInstanceMethod(class, selector);
    method_exchangeImplementations(m2, m1);
}

@end
