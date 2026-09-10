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

  /* An entry point that signalled leaves an empty window and a message on a
     console that, on a phone, nobody is reading. Put it on screen instead:
     the condition is the one thing worth having, and a rebuild to find it is
     the most expensive minute in the whole loop. */
  NSString *failure = [ECLBoot evaluate:@"(ios-app-runtime:boot-failure)"];
  if (failure.length > 2) {          /* "" prints as two quote characters */
    [self showBootFailure:failure];
    return YES;
  }

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

- (void)showBootFailure:(NSString *)failure
{
  UIViewController *controller = self.window.rootViewController;
  UITextView *view = [[UITextView alloc] init];
  view.translatesAutoresizingMaskIntoConstraints = NO;
  view.editable = NO;
  view.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
  view.textColor = UIColor.labelColor;
  view.backgroundColor = UIColor.systemBackgroundColor;
  /* Read back through the Lisp printer, so escapes and newlines survive the
     round trip rather than arriving as backslash-n. */
  view.text = [failure stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
  [controller.view addSubview:view];

  UILayoutGuide *safe = controller.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [view.topAnchor constraintEqualToAnchor:safe.topAnchor constant:8],
    [view.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-8],
    [view.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:12],
    [view.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-12],
  ]];
}

@end
