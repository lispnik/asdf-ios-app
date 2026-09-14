#import "SceneAppDelegate.h"
#import "ECLBoot.h"

/* ------------------------------------------------------------------
 * The application delegate: with scenes, nearly nothing. */

@implementation SceneAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)options
{
  return YES;
}

- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session
                                   options:(UISceneConnectionOptions *)options
{
  /* The name matches UISceneConfigurations in Info.plist, which the
     example's .asd merges in through :BUNDLE-INFO-PLIST. */
  UISceneConfiguration *configuration =
    [[UISceneConfiguration alloc] initWithName:@"Default" sessionRole:session.role];
  configuration.delegateClass = SceneDelegate.class;
  return configuration;
}

@end

/* ------------------------------------------------------------------
 * The scene delegate: the window, the boot, and the lifecycle. */

static BOOL sBooted = NO;

/* Every event goes to one Lisp function, by name.  -evaluate: never throws,
   so a Lisp error here is a string on the console and not a crash. */
static void Tell(NSString *event)
{
  if (sBooted) {
    (void)[ECLBoot evaluate:[NSString stringWithFormat:@"(scene-ios:lifecycle :%@)", event]];
  }
}

@implementation SceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)options
{
  UIWindowScene *windowScene = (UIWindowScene *)scene;
  self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
  self.window.rootViewController = [[UIViewController alloc] init];
  self.window.rootViewController.view.backgroundColor = UIColor.systemBackgroundColor;
  [self.window makeKeyAndVisible];

  /* The same steps as the shipped delegate: boot, and put a failed entry
     point on screen rather than on a console nobody is reading. */
  [ECLBoot boot];
  NSString *failure = [ECLBoot evaluate:@"(ios-app-runtime:boot-failure)"];
  if (failure.length > 2) {
    UITextView *view = [[UITextView alloc] initWithFrame:self.window.rootViewController.view.bounds];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.editable = NO;
    view.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
    view.text = [failure stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
    [self.window.rootViewController.view addSubview:view];
    return;
  }
  sBooted = YES;
  Tell(@"will-connect");
}

- (void)sceneDidBecomeActive:(UIScene *)scene       { Tell(@"did-become-active"); }
- (void)sceneWillResignActive:(UIScene *)scene      { Tell(@"will-resign-active"); }
- (void)sceneWillEnterForeground:(UIScene *)scene   { Tell(@"will-enter-foreground"); }
- (void)sceneDidEnterBackground:(UIScene *)scene    { Tell(@"did-enter-background"); }
- (void)sceneDidDisconnect:(UIScene *)scene         { Tell(@"did-disconnect"); }

@end
