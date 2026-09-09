/* ECLBoot.h -- starting the Lisp image, and talking to it.
 *
 * Foundation and <ecl/ecl.h> only. UIKit must never reach this translation
 * unit: ECL's headers define bare `t' and other very short names, and the
 * collision is not subtle. Anything that needs a view goes in a file that
 * imports this header instead of ecl.h. */

#import <Foundation/Foundation.h>

@interface ECLBoot : NSObject

/* Boots the image and runs the application's entry point. Once, from the main
   thread, before anything else here. */
+ (void)boot;

/* Reads, evaluates and prints one form. Never throws: a Lisp error comes back
   as its printed representation, because a condition unwinding through an
   Objective-C frame corrupts the frame state. */
+ (NSString *)evaluate:(NSString *)source;

/* Evaluates on the main thread and waits. UIKit is main-thread only, and a
   Lisp worker -- or a remote REPL -- is not on it. */
+ (void)evaluateOnMain:(NSString *)source;

@end
