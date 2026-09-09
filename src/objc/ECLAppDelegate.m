#import "ECLAppDelegate.h"
#import "ECLBoot.h"

#import "ios-app-build.h"

@implementation ECLAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)options
{
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

  /* A root view controller before booting, so that a Lisp entry point which
     fails still leaves something on screen rather than a black rectangle with
     no explanation. */
  self.window.rootViewController = [[UIViewController alloc] init];
  self.window.rootViewController.view.backgroundColor = UIColor.systemBackgroundColor;
  [self.window makeKeyAndVisible];

  /* Boots the image and calls the application's entry point, which runs on
     this thread and must RETURN -- the run loop has not started yet. */
  [ECLBoot boot];

  /* If the entry point installed a view controller of its own, use it. */
  Class controllerClass = Nil;
  NSString *name = [ECLBoot evaluate:@"(ios-app-runtime:root-view-controller-name)"];
  if (name.length > 0) {
    controllerClass = NSClassFromString(name);
  }
  if (controllerClass != Nil) {
    self.window.rootViewController = [[controllerClass alloc] init];
  }
  return YES;
}

@end
