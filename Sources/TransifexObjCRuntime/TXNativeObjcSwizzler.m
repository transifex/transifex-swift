//
//  TXNativeObjcSwizzler.m
//  Transifex
//
//  Created by Stelios Petrakis on 5/11/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

#import <objc/runtime.h>
#import "TXNativeObjcSwizzler.h"

static const NSString *kInvalidConversionSpecifier = @"INVALID";

static NSString *(^TXNativeObjcSwizzlerClosure)(NSString *, NSArray <id> *);

@implementation NSString (TXNativeObjcSwizzler)

+ (instancetype)swizzledLocalizedStringWithFormat:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2) {
    // Match all %{something} specifiers in the format string via a regular
    // expression.
    //
    // The regular expression matches any character combinations that start with
    // the character '%' followed by at least one non-whitespace character (\S+)
    NSString *regExPattern = @"\%\\S+";
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:regExPattern
        options:0
        error:&error];
    
    if (error) {
        NSLog(@"%s Error: %@",
              __PRETTY_FUNCTION__,
              error);
        
        return TXNativeObjcSwizzlerClosure(format,
                                           @[]);
    }
    
    va_list argumentList;
    va_start(argumentList, format);
    
    NSRange totalRange = NSMakeRange(0, format.length);
    NSMutableArray <TXNativeObjcArgument *> *arguments = [NSMutableArray new];
    
    for (NSTextCheckingResult *match in [regex matchesInString:format
                                                       options:0
                                                         range:totalRange]) {
        NSRange matchRange = match.range;
        NSString *originalMatchString = [format substringWithRange:matchRange];

        // Look into what's after the % character
        NSRange matchRangePlusOne = NSMakeRange(matchRange.location + 1,
                                                matchRange.length - 1);
        NSString *matchString = [format substringWithRange:matchRangePlusOne].lowercaseString;

        TXNativeObjcArgument *arg = [TXNativeObjcArgument new];

        // Integer (%d, %D)
        if ([matchString containsString:@"d"]) {
            int intObject = va_arg(argumentList, int);
            arg.value = @(intObject);
            arg.type = TXNativeObjcArgumentTypeInt;
        }
        // Unsigned (%u, %U)
        else if ([matchString containsString:@"u"]) {
            unsigned unsignedObject = va_arg(argumentList, unsigned);
            arg.value = @(unsignedObject);
            arg.type = TXNativeObjcArgumentTypeUnsigned;
        }
        // Double (%e, %E, %g, %G, %a, %A, %f, %F)
        else if ([matchString containsString:@"e"]
                 || [matchString containsString:@"g"]
                 || [matchString containsString:@"a"]
                 || [matchString containsString:@"f"]) {
            double doubleObject = va_arg(argumentList, double);
            arg.value = @(doubleObject);
            arg.type = TXNativeObjcArgumentTypeDouble;
        }
        // Character (%c, %C)
        else if ([matchString containsString:@"c"]) {
            int charObject = va_arg(argumentList, int);
            NSString *stringObject = [NSString stringWithFormat:originalMatchString,
                                      charObject];
            arg.value = stringObject;
            arg.type = TXNativeObjcArgumentTypeChar;
        }
        // C String (%s, %S)
        else if ([matchString containsString:@"s"]) {
            char *charObject = va_arg(argumentList, char *);
            NSString *stringObject = [NSString stringWithUTF8String:charObject];
            arg.value = stringObject;
            arg.type = TXNativeObjcArgumentTypeCString;
        }
        // Objective-C object (%@)
        else if ([matchString isEqualToString:@"@"]) {
            NSString *stringObject = (NSString *)va_arg(argumentList, id);
            arg.value = stringObject;
            arg.type = TXNativeObjcArgumentTypeObject;
        }
        // '%' character (%%)
        else if ([matchString isEqualToString:@"%"]){
            arg.value = @"%";
            arg.type = TXNativeObjcArgumentTypePercent;
        }
        // If there's a conversion specifier that the logic isn't handling yet,
        // fallbak to an invalid string constant.
        else {
            arg.value = kInvalidConversionSpecifier;
            arg.type = TXNativeObjcArgumentTypeInvalid;
        }
        
        [arguments addObject:arg];
        
        // Ignored conversion specifiers:
        // %x, %X (hexademical)
        // %o, %O (octal)
        // %p (pointer)
        //
        // Other specifiers / modifiers that need to be tested:
        // * Positional specifiers (e.g. %1$@, %2%s etc)
        // * Length modifiers (e.g. %llu, %ld etc)
        //
        // Ref:
        // * https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFStrings/formatSpecifiers.html
        // * https://pubs.opengroup.org/onlinepubs/009695399/functions/printf.html
    }
    
    va_end(argumentList);
    
    return TXNativeObjcSwizzlerClosure(format,
                                       arguments);
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
