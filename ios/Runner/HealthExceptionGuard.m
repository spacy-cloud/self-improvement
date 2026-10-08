#import "HealthExceptionGuard.h"

@implementation HealthExceptionGuard

+ (nullable NSString *)runAndCatch:(NS_NOESCAPE void (^)(void))block {
  @try {
    block();
    return nil;
  } @catch (NSException *exception) {
    return exception.reason ?: exception.name;
  }
}

@end
