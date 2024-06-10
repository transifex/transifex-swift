//
//  TXNativeObjcSwizzler.h
//  Transifex
//
//  Created by Stelios Petrakis on 5/11/20.
//  Copyright © 2020 Transifex. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The type of the extracted argument
typedef NS_ENUM(NSInteger, TXNativeObjcArgumentType) {
    TXNativeObjcArgumentTypeInvalid = -1,
    TXNativeObjcArgumentTypeInt,
    TXNativeObjcArgumentTypeUnsigned,
    TXNativeObjcArgumentTypeDouble,
    TXNativeObjcArgumentTypeChar,
    TXNativeObjcArgumentTypeCString,
    TXNativeObjcArgumentTypeObject,
    TXNativeObjcArgumentTypePercent
};

/// Wrapper class that contains the information about the extracted argument value and its type
@interface TXNativeObjcArgument : NSObject

/// The value of the extracted argument
@property (nullable) id value;

/// The type of the extracted argument
@property TXNativeObjcArgumentType type;

@end

/// Responsible for swizzling Objective C NSString localizedStringWithFormat: method when activated.
@interface TXNativeObjcSwizzler : NSObject

/// Activate swizzling for Objective C NSString.localizedStringWithFormat: method that calls the passed block
/// when the method is called.
///
/// @param closure A provided block that will be called when the localizedStringWithFormat: method
/// is called.
+ (void)swizzleLocalizedStringWithClosure:(NSString* (^)(NSString *format,
                                                         NSArray <TXNativeObjcArgument *> *arguments))closure;

/// Deactivate swizzling for Objective C NSString.localizedStringWithFormat: method.
+ (void)revertLocalizedString;

/// Swizzle the `localizedAttributedStringForKey:value:table:` NSBundle method using
/// the provided class and method from the caller.
///
/// @param class The caller class that contains the swizzled selector.
/// @param selector The swizzled selector.
+ (void)swizzleLocalizedAttributedString:(Class)class selector:(SEL)selector;

/// Deactivate swizzling for `localizedAttributedStringForKey:value:table:` NSBundle
/// method.
///
/// @param class The caller class that contains the swizzled selector.
/// @param selector The swizzled selector.
+ (void)revertLocalizedAttributedString:(Class)class selector:(SEL)selector;

@end

NS_ASSUME_NONNULL_END
