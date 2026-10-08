#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs a block and reports an Objective-C exception instead of letting it end
/// the app (BS-122).
///
/// HealthKit does not answer with an error when the build lacks the HealthKit
/// entitlement or the usage description of the Info.plist: the call raises an
/// `NSException`, and Swift cannot catch that. Every HealthKit call of
/// `HealthStepsPlugin` that can raise runs inside this guard, so such a build
/// answers "not available" instead of crashing.
@interface HealthExceptionGuard : NSObject

/// Calls `block`. Returns nil when it finished normally, otherwise the reason
/// of the exception it raised (the name when there is no reason). The text is
/// only read on the native side to choose a fixed error code; it is never
/// passed on to Dart.
+ (nullable NSString *)runAndCatch:(NS_NOESCAPE void (^)(void))block;

@end

NS_ASSUME_NONNULL_END
