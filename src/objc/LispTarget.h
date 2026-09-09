/* LispTarget.h -- strategy 1: a generic Objective-C target that forwards
   target-action callbacks into Lisp.

   Covers everything in UIKit that uses the target/selector protocol:
   UIControl actions, UIGestureRecognizer, NSTimer, NSNotificationCenter. */

#import <Foundation/Foundation.h>

@interface LispTarget : NSObject

/* The Lisp form evaluated on every callback. */
@property (nonatomic, copy) NSString *form;

/* Instances are kept alive by the class -- see the note in the .m. */
+ (instancetype)targetWithForm:(NSString *)form;

/* The action selector: @selector(fire:). */
- (void)fire:(id)sender;

@end
