#import "AppDelegate.h"
#import "MainViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    BOOL isDark = YES;
    id storedDarkMode = [[NSUserDefaults standardUserDefaults] objectForKey:@"dark_mode"];
    if (storedDarkMode != nil) {
        isDark = [storedDarkMode boolValue];
    }
    self.window.backgroundColor = isDark
        ? [UIColor colorWithRed:0.075 green:0.102 blue:0.133 alpha:1]
        : [UIColor colorWithRed:0.941 green:0.957 blue:0.973 alpha:1];

    MainViewController *main = [[MainViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:main];
    nav.navigationBarHidden = YES;

    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

@end
