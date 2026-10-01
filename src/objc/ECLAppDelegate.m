#import "ECLAppDelegate.h"
#import "ECLBoot.h"

#import "ios-app-build.h"

/* ------------------------------------------------------------------
 * The application delegate: with scenes, nearly nothing.  UIKit asks it
 * which class handles a scene; the answer is also in Info.plist, and the two
 * agree.  The window is not made here -- an app delegate that makes its own
 * window under a scene manifest gets two, one of them blank. */

@implementation ECLAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)options
{
  return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session
                                   options:(UISceneConnectionOptions *)options
{
  UISceneConfiguration *configuration =
    [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
  configuration.delegateClass = ECLSceneDelegate.class;
  return configuration;
}

@end

/* ------------------------------------------------------------------
 * The scene delegate: the window, the boot, and the entry point. */

/* A URL the system handed the application, to Lisp.
 *
 * A document's URL is security scoped: the file can be read only between
 * start and stop.  So access is held across the call, and what the hook wants
 * of the file it takes before it returns -- IOS-APP-RUNTIME:*OPEN-URL-HOOK*
 * says so.  The URL goes over as a string literal in a form; -absoluteString
 * is percent-encoded, and the two characters that could still end the literal
 * early are escaped anyway. */
static void DeliverURL(NSURL *url)
{
  BOOL scoped = url.isFileURL && [url startAccessingSecurityScopedResource];
  NSString *literal =
    [[url.absoluteString stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
      stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];
  (void)[ECLBoot evaluate:[NSString stringWithFormat:
                             @"(ios-app-runtime:deliver-url \"%@\")", literal]];
  if (scoped) {
    [url stopAccessingSecurityScopedResource];
  }
}

@implementation ECLSceneDelegate
{
  BOOL _booted;
}

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)options
{
  UIWindowScene *windowScene = (UIWindowScene *)scene;
  self.window = [[UIWindow alloc] initWithWindowScene:windowScene];

  /* A root view controller before booting, so that a Lisp entry point which
     fails still leaves something on screen rather than a black rectangle with
     no explanation. */
  self.window.rootViewController = [[UIViewController alloc] init];
  self.window.rootViewController.view.backgroundColor = UIColor.systemBackgroundColor;
  [self.window makeKeyAndVisible];

  /* Boots the image and calls the application's entry point, which runs on
     this thread and must RETURN -- the run loop is between events. */
  [ECLBoot boot];

  /* An entry point that signalled leaves an empty window and a message on a
     console that, on a phone, nobody is reading. Put it on screen instead:
     the condition is the one thing worth having, and a rebuild to find it is
     the most expensive minute in the whole loop. */
  NSString *failure = [ECLBoot evaluate:@"(ios-app-runtime:boot-failure)"];
  if (failure.length > 2) {          /* "" prints as two quote characters */
    [self showBootFailure:failure];
    return;
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

  /* A URL that LAUNCHED the application arrives with the connection and by
     no other route: -scene:openURLContexts: is not sent for it.  After the
     entry point, which is where the hook is set. */
  _booted = YES;
  for (UIOpenURLContext *context in options.URLContexts) {
    DeliverURL(context.URL);
  }
}

/* A URL that arrives while the application is running. */
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)contexts
{
  if (!_booted) {
    return;          /* the entry point failed; there is nobody to tell */
  }
  for (UIOpenURLContext *context in contexts) {
    DeliverURL(context.URL);
  }
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
