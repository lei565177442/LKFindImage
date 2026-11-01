//
//  LKFIEntry.m
//  插件入口：等 App 启动完成后挂载悬浮球
//

#import "LKFICommon.h"

static void LKFIBoot(void)
{
    // 扩展进程里不启用
    NSString *bundlePath = [NSBundle mainBundle].bundlePath ?: @"";
    if ([bundlePath hasSuffix:@".appex"]) return;

    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidFinishLaunchingNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *note) {
        [LKFIWindows ensureSetup];
    }];

    // 兜底：如果通知已经错过（热注入 / 二次加载），延时再挂一次
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [LKFIWindows ensureSetup];
    });
}

__attribute__((constructor))
static void LKFIEntryConstructor(void)
{
    @autoreleasepool {
        if (NSClassFromString(@"UIApplication") == nil) return;
        LKFIBoot();
    }
}
