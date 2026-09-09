#import "LispTarget.h"
#import "ECLBoot.h"

/* UIKit holds targets *weakly*, and Lisp holds nothing but a raw address, so a
   target wired up from Lisp would be deallocated before the first tap and the
   control would message a zombie. Parking every instance here is the whole
   reason +targetWithForm: exists rather than a plain init. A real app would
   want to unregister them; a prototype can leak. */
static NSMutableSet<LispTarget *> *sLiveTargets;

@implementation LispTarget

+ (void)initialize
{
  if (self == LispTarget.class) {
    sLiveTargets = [NSMutableSet set];
  }
}

+ (instancetype)targetWithForm:(NSString *)form
{
  LispTarget *target = [[LispTarget alloc] init];
  target.form = form;
  [sLiveTargets addObject:target];
  return target;
}

- (void)fire:(id)sender
{
  /* -evaluate: goes through si_safe_eval, so a Lisp error comes back as a
     string rather than unwinding through UIKit's stack frames, which would
     corrupt them. Nothing here may throw. */
  (void)[ECLBoot evaluate:self.form];
}

@end
