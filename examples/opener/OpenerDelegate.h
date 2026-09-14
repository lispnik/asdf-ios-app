/* OpenerDelegate.h -- a scene-based delegate that hands URLs to Lisp.
 *
 * The same shape as examples/scene, with one addition: a URL that opens
 * the app -- a lisp:// link, or a .lisp document from Files or a share
 * sheet -- reaches Lisp through OPENER:OPEN-URL, whether it arrives with
 * the launch or while the app is running. */

#import <UIKit/UIKit.h>

@interface OpenerAppDelegate : UIResponder <UIApplicationDelegate>
@end

@interface OpenerSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (strong, nonatomic) UIWindow *window;
@end
