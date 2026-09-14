/* ECLAppDelegate.h -- the application delegate and the scene delegate.
 *
 * UIScene is the lifecycle: the application delegate names the scene
 * delegate and nothing more, and the scene delegate makes the window, boots
 * the image, and puts a failed entry point on screen.  The generated
 * Info.plist carries the UIApplicationSceneManifest that points UIKit at
 * ECLSceneDelegate; an application with a delegate of its own supplies both
 * halves, as examples/scene does. */

#import <UIKit/UIKit.h>

@interface ECLAppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface ECLSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end
