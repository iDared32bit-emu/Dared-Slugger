/*
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at https://mozilla.org/MPL/2.0/.
 */

// Dared Slugger: a small OpenGL ES 1.1 homebrew game for iPhone OS
// 2.x. See README.md for how to build it.

#include "BaseballView.h"
#include "Sound.h"
#include "System.h"

@interface DaredSluggerAppDelegate : NSObject {
  UIWindow *window;
  BaseballView *view;
}
@end

@implementation DaredSluggerAppDelegate

- (void)applicationDidFinishLaunching:(UIApplication *)application {
  [application setStatusBarHidden:YES];
  SoundInit();
  window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  view = [[BaseballView alloc] initWithFrame:[window bounds]];
  [window addSubview:view];
  [window makeKeyAndVisible];
  [NSTimer scheduledTimerWithTimeInterval:(1.0 / 60.0)
                                   target:self
                                 selector:@selector(onTick:)
                                 userInfo:nil
                                  repeats:YES];
}

- (void)onTick:(NSTimer *)timer {
  [view tick];
}

- (void)dealloc {
  [view release];
  [window release];
  [super dealloc];
}

@end

int main(int argc, char *argv[]) {
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  int result = UIApplicationMain(
      argc, argv, nil, NSStringFromClass([DaredSluggerAppDelegate class]));
  [pool drain];
  return result;
}
