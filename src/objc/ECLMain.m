/* ECLMain.m -- main().
 *
 * Suppressed entirely when a system sets :BUNDLE-OBJC-MAIN, so that an
 * application which needs its own main() is not fighting this one. */

#import <UIKit/UIKit.h>

#import "ios-app-build.h"

int main(int argc, char *argv[])
{
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, @IOS_APP_DELEGATE);
  }
}
