/* SceneAppDelegate.h -- an application delegate that uses UIScene.
 *
 * The delegate asdf-ios-app ships makes its window in
 * -application:didFinishLaunchingWithOptions:, the pre-iOS 13 way, and UIKit
 * now logs at every launch that "UIScene lifecycle will soon be required".
 * This pair of classes is the scene-based way: the application delegate only
 * names the scene delegate, and the scene delegate makes the window, boots
 * the image, and forwards every lifecycle event to Lisp. */

#import <UIKit/UIKit.h>

@interface SceneAppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end
