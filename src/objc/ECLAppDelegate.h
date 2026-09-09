/* ECLAppDelegate.h -- the default delegate.
 *
 * UIKit and ECLBoot.h, never <ecl/ecl.h>. Replace it wholesale with
 * :BUNDLE-APP-DELEGATE if you want your own. */

#import <UIKit/UIKit.h>

@interface ECLAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end
