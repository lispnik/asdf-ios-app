/* SceneAppDelegate.h -- an application delegate that uses UIScene.
 *
 * The delegate asdf-ios-app ships is scene based too, and this pair is what
 * an application does when it wants the lifecycle for itself: the
 * application delegate only names the scene delegate, and the scene delegate
 * makes the window, boots the image, and forwards every lifecycle event to
 * Lisp -- which the shipped one does not. */

#import <UIKit/UIKit.h>

@interface SceneAppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface SceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end
