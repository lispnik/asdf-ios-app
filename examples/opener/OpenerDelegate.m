#import "OpenerDelegate.h"
#import "ECLBoot.h"

@implementation OpenerAppDelegate

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
  configuration.delegateClass = OpenerSceneDelegate.class;
  return configuration;
}

@end

static BOOL sBooted = NO;

/* A URL to Lisp, as a string literal in a form.  A document URL is
   security scoped: the file can be read only between start and stop, so
   the read happens on this side and the CONTENTS go over, with the path
   for the record. */
static void Open(NSURL *url)
{
  if (!sBooted) return;
  NSString *contents = @"";
  if (url.isFileURL) {
    BOOL scoped = [url startAccessingSecurityScopedResource];
    contents = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:NULL] ?: @"";
    if (scoped) [url stopAccessingSecurityScopedResource];
  }
  NSString *quote = @"\\\"";
  NSString *(^literal)(NSString *) = ^(NSString *s) {
    return [[s stringByReplacingOccurrencesOfString:@"\\" withString:@"\\\\"]
            stringByReplacingOccurrencesOfString:@"\"" withString:quote];
  };
  (void)[ECLBoot evaluate:[NSString stringWithFormat:@"(opener:open-url \"%@\" \"%@\")",
                           literal(url.absoluteString), literal(contents)]];
}

@implementation OpenerSceneDelegate

- (void)scene:(UIScene *)scene
    willConnectToSession:(UISceneSession *)session
                 options:(UISceneConnectionOptions *)options
{
  self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
  self.window.rootViewController = [[UIViewController alloc] init];
  self.window.rootViewController.view.backgroundColor = UIColor.systemBackgroundColor;
  [self.window makeKeyAndVisible];
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
  /* A URL that launched the app arrives with the connection. */
  for (UIOpenURLContext *context in options.URLContexts) {
    Open(context.URL);
  }
}

/* A URL that arrives while the app is running. */
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)contexts
{
  for (UIOpenURLContext *context in contexts) {
    Open(context.URL);
  }
}

@end
