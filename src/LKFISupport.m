//
//  LKFISupport.m
//  窗口管理 / 图像工具 / 截屏 / 模板存储 / 点击注入
//

#import "LKFICommon.h"
#import <dlfcn.h>
#import <unistd.h>
#import <stdlib.h>
#import <math.h>
#import <mach/mach_time.h>

NSString *LKFIStrategyName(LKFIStrategy s)
{
    switch (s) {
        case LKFIStrategyBestScore:   return @"最高分";
        case LKFIStrategyLeftmost:    return @"最左";
        case LKFIStrategyTopmost:     return @"最上";
        case LKFIStrategyRightmost:   return @"最右";
        case LKFIStrategyBottommost:  return @"最下";
        case LKFIStrategyRandom:      return @"随机";
    }
    return @"最高分";
}

/* =====================================================================
 *  窗口
 * ===================================================================== */

@implementation LKFIOverlayWindow

- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeFirstResponder { return NO; }

@end

static NSMutableArray<UIWindow *> *gLKFIWindows = nil;

@interface LKFIWindows ()
+ (NSMutableArray<UIWindow *> *)registry;
@end

@implementation LKFIWindows

+ (NSMutableArray<UIWindow *> *)registry
{
    if (!gLKFIWindows) gLKFIWindows = [NSMutableArray array];
    return gLKFIWindows;
}

+ (void)registerWindow:(UIWindow *)w
{
    if (!w) return;
    if (![[self registry] containsObject:w]) [[self registry] addObject:w];
}

+ (void)unregisterWindow:(UIWindow *)w
{
    if (!w) return;
    [[self registry] removeObject:w];
}

+ (NSArray<UIWindow *> *)ourWindows
{
    return [[self registry] copy];
}

+ (NSArray<UIWindow *> *)hideOurs
{
    NSMutableArray *visible = [NSMutableArray array];
    for (UIWindow *w in [self ourWindows]) {
        if (!w.hidden && w.alpha > 0.01) {
            [visible addObject:w];
            w.hidden = YES;
        }
    }
    return visible;
}

+ (void)restoreOurs:(NSArray<UIWindow *> *)wins
{
    for (UIWindow *w in wins) w.hidden = NO;
}

+ (UIWindow *)hostWindow
{
    NSArray *ours = [self ourWindows];
    UIApplication *app = UIApplication.sharedApplication;
    UIWindow *keyWin = nil;
    UIWindow *normalWin = nil;
    UIWindow *anyWin = nil;

    NSMutableArray<UIWindow *> *all = [NSMutableArray array];

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in app.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            UIWindowScene *ws = (UIWindowScene *)scene;
            for (UIWindow *w in ws.windows) [all addObject:w];
        }
    }
    if (all.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [all addObjectsFromArray:app.windows];
#pragma clang diagnostic pop
    }

    for (UIWindow *w in all) {
        if ([ours containsObject:w]) continue;
        if (!anyWin) anyWin = w;
        if (w.isKeyWindow && !keyWin) keyWin = w;
        if (!normalWin && fabs(w.windowLevel - UIWindowLevelNormal) < 0.5) normalWin = w;
    }

    if (keyWin) return keyWin;
    if (normalWin) return normalWin;
    return anyWin;
}

+ (UIWindow *)newOverlayWindowAtLevel:(UIWindowLevel)level
{
    UIWindow *w = [[LKFIOverlayWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    w.windowLevel = level;
    w.backgroundColor = [UIColor clearColor];
    w.opaque = NO;

    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor clearColor];
    w.rootViewController = vc;

    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if ([scene isKindOfClass:[UIWindowScene class]]) {
                w.windowScene = (UIWindowScene *)scene;
                break;
            }
        }
    }

    [self registerWindow:w];
    w.hidden = NO;
    return w;
}

+ (void)ensureSetup
{
    static BOOL done = NO;

    dispatch_async(dispatch_get_main_queue(), ^{
        // 补挂 windowScene：早于 UI 就绪时创建的窗口可能没挂上，挂不上就不显示
        UIWindowScene *scene = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
                if ([s isKindOfClass:[UIWindowScene class]]) { scene = (UIWindowScene *)s; break; }
            }
        }
        if (scene) {
            for (UIWindow *w in [LKFIWindows ourWindows]) {
                if (w.windowScene == nil) w.windowScene = scene;
            }
        }

        if (done) return;
        done = YES;

        // 悬浮球：窗口只占球那么大，球以外的地方不会挡住宿主 App 的触摸
        CGRect sb = UIScreen.mainScreen.bounds;
        CGFloat bw = 56.0;
        CGRect ballFrame = CGRectMake(sb.size.width - bw - 12, sb.size.height * 0.35, bw, bw);

        UIWindow *ballWin = [LKFIWindows newOverlayWindowAtLevel:UIWindowLevelAlert + 20];
        ballWin.frame = ballFrame;

        LKFIFloatBall *ball = [[LKFIFloatBall alloc] initWithFrame:ballWin.bounds];
        [ballWin.rootViewController.view addSubview:ball];

        LKFI_LOG("ready v%@", LKFI_VERSION);
    });
}

@end

/* =====================================================================
 *  图像工具
 * ===================================================================== */

@implementation LKFIImageUtil

+ (UIImage *)cropImage:(UIImage *)img toPixelRect:(CGRect)r
{
    CGImageRef cg = img.CGImage;
    if (!cg) return nil;

    CGFloat W = (CGFloat)CGImageGetWidth(cg);
    CGFloat H = (CGFloat)CGImageGetHeight(cg);
    CGRect full = CGRectMake(0, 0, W, H);

    r = CGRectIntegral(CGRectIntersection(r, full));
    if (r.size.width < 4 || r.size.height < 4) return nil;

    CGImageRef sub = CGImageCreateWithImageInRect(cg, r);
    if (!sub) return nil;

    UIImage *out = [UIImage imageWithCGImage:sub scale:img.scale orientation:img.imageOrientation];
    CGImageRelease(sub);
    return out;
}

+ (uint8_t *)grayCopyOfCGImage:(CGImageRef)cg width:(int *)ow height:(int *)oh
{
    if (!cg) return NULL;

    int w = (int)CGImageGetWidth(cg);
    int h = (int)CGImageGetHeight(cg);
    if (w <= 0 || h <= 0) return NULL;

    size_t bpr = (size_t)w * 4;
    uint8_t *rgba = (uint8_t *)calloc((size_t)h, bpr);
    if (!rgba) return NULL;

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(rgba, (size_t)w, (size_t)h, 8, bpr, cs,
                                             kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);

    if (!ctx) { free(rgba); return NULL; }

    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, w, h));
    CGContextDrawImage(ctx, CGRectMake(0, 0, w, h), cg);
    CGContextRelease(ctx);

    uint8_t *gray = (uint8_t *)malloc((size_t)w * (size_t)h);
    if (!gray) { free(rgba); return NULL; }

    int total = w * h;
    for (int i = 0; i < total; i++) {
        int rr = rgba[i * 4 + 0];
        int gg = rgba[i * 4 + 1];
        int bb = rgba[i * 4 + 2];
        gray[i] = (uint8_t)((77 * rr + 151 * gg + 29 * bb) >> 8);
    }
    free(rgba);

    if (ow) *ow = w;
    if (oh) *oh = h;
    return gray;
}

@end

/* =====================================================================
 *  截屏
 * ===================================================================== */

@implementation LKFICapture

+ (UIImage *)captureHostWindow
{
    UIWindow *win = [LKFIWindows hostWindow];
    if (!win) {
        LKFI_LOG("capture: no host window");
        return nil;
    }

    NSArray *hidden = [LKFIWindows hideOurs];

    UIImage *img = nil;
    UIGraphicsBeginImageContextWithOptions(win.bounds.size, NO, 0);
    BOOL ok = [win drawViewHierarchyInRect:win.bounds afterScreenUpdates:YES];
    if (ok) img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    if (!img) {
        LKFI_LOG("capture: drawViewHierarchy failed, fallback to renderInContext");
        UIGraphicsBeginImageContextWithOptions(win.bounds.size, NO, 0);
        CGContextRef c = UIGraphicsGetCurrentContext();
        if (c) [win.layer renderInContext:c];
        img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }

    [LKFIWindows restoreOurs:hidden];
    return img;
}

@end

/* =====================================================================
 *  模板存储
 * ===================================================================== */

@implementation LKFITemplate
@end

@implementation LKFITemplateStore
{
    NSMutableArray<LKFITemplate *> *_items;
}

+ (instancetype)shared
{
    static LKFITemplateStore *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[LKFITemplateStore alloc] init]; });
    return s;
}

- (instancetype)init
{
    if ((self = [super init])) {
        _items = [NSMutableArray array];
        [self reloadIndex];
    }
    return self;
}

- (NSString *)dirPath
{
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (!docs) docs = NSTemporaryDirectory();
    NSString *dir = [docs stringByAppendingPathComponent:@"LKFindImage/templates"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:NULL];
    return dir;
}

- (NSString *)indexPath
{
    return [[self dirPath] stringByAppendingPathComponent:@"index.json"];
}

- (void)reloadIndex
{
    [_items removeAllObjects];
    NSData *data = [NSData dataWithContentsOfFile:[self indexPath]];
    if (!data) return;

    id obj = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![obj isKindOfClass:[NSArray class]]) return;

    for (NSDictionary *d in (NSArray *)obj) {
        if (![d isKindOfClass:[NSDictionary class]]) continue;
        LKFITemplate *t = [[LKFITemplate alloc] init];
        t.name = d[@"name"] ?: @"模板";
        t.path = [[self dirPath] stringByAppendingPathComponent:(d[@"file"] ?: @"")];
        t.pixelSize = CGSizeMake([d[@"w"] floatValue], [d[@"h"] floatValue]);
        if ([[NSFileManager defaultManager] fileExistsAtPath:t.path]) [_items addObject:t];
    }
}

- (void)persist
{
    NSMutableArray *arr = [NSMutableArray array];
    for (LKFITemplate *t in _items) {
        [arr addObject:@{
            @"name": t.name ?: @"",
            @"file": t.path.lastPathComponent ?: @"",
            @"w": @(t.pixelSize.width),
            @"h": @(t.pixelSize.height)
        }];
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:arr options:0 error:NULL];
    [data writeToFile:[self indexPath] atomically:YES];
}

- (NSArray<LKFITemplate *> *)allTemplates
{
    return [_items copy];
}

- (NSString *)nextTemplateName
{
    int i = 1;
    while (YES) {
        NSString *name = [NSString stringWithFormat:@"模板%d", i];
        BOOL used = NO;
        for (LKFITemplate *t in _items) {
            if ([t.name isEqualToString:name]) { used = YES; break; }
        }
        if (!used) return name;
        i++;
        if (i > 9999) return [NSString stringWithFormat:@"模板%lu", (unsigned long)_items.count + 1];
    }
}

- (LKFITemplate *)saveImage:(UIImage *)image name:(NSString *)name
{
    if (!image || !image.CGImage) return nil;

    if (name.length == 0) name = [self nextTemplateName];

    NSData *png = UIImagePNGRepresentation(image);
    if (!png) return nil;

    NSString *file = [NSString stringWithFormat:@"tpl_%.0f.png",
                      [[NSDate date] timeIntervalSince1970] * 1000.0];
    NSString *path = [[self dirPath] stringByAppendingPathComponent:file];

    if (![png writeToFile:path atomically:YES]) return nil;

    LKFITemplate *t = [[LKFITemplate alloc] init];
    t.name = name;
    t.path = path;
    t.pixelSize = CGSizeMake(CGImageGetWidth(image.CGImage), CGImageGetHeight(image.CGImage));

    [_items addObject:t];
    [self persist];
    return t;
}

- (void)removeTemplate:(LKFITemplate *)tpl
{
    if (!tpl) return;
    [[NSFileManager defaultManager] removeItemAtPath:tpl.path error:NULL];
    [_items removeObject:tpl];
    [self persist];
}

- (UIImage *)imageForTemplate:(LKFITemplate *)tpl
{
    if (!tpl) return nil;
    return [UIImage imageWithContentsOfFile:tpl.path];
}

@end

/* =====================================================================
 *  点击注入（私有 IOHIDEvent，需宿主 App 具备 HID 派发权限）
 * ===================================================================== */

typedef void *(*LKFI_FnClientCreate)(CFAllocatorRef);
typedef void  (*LKFI_FnDispatch)(void *, void *);
// (allocator, timeStamp, type, index, identity, eventMask, buttonMask,
//  x, y, z, tipPressure, twist, range, touch, options)
typedef void *(*LKFI_FnCreateDigitizer)(CFAllocatorRef, uint64_t, uint32_t, uint32_t,
                                        uint32_t, uint32_t, uint32_t, double, double,
                                        double, double, double, int, int, uint32_t);
// (allocator, timeStamp, index, identity, eventMask,
//  x, y, z, tipPressure, twist, range, touch, options)
typedef void *(*LKFI_FnCreateFinger)(CFAllocatorRef, uint64_t, uint32_t, uint32_t,
                                     uint32_t, double, double, double, double,
                                     double, int, int, uint32_t);
typedef void  (*LKFI_FnAppend)(void *, void *);
typedef void  (*LKFI_FnSetInteger)(void *, uint32_t, int64_t);
typedef void  (*LKFI_FnSetSender)(void *, uint64_t);

static LKFI_FnClientCreate      g_fnClientCreate   = NULL;
static LKFI_FnDispatch          g_fnDispatch       = NULL;
static LKFI_FnCreateDigitizer   g_fnCreateDigitizer= NULL;
static LKFI_FnCreateFinger      g_fnCreateFinger   = NULL;
static LKFI_FnAppend            g_fnAppend         = NULL;
static LKFI_FnSetInteger        g_fnSetInteger     = NULL;
static LKFI_FnSetSender         g_fnSetSender      = NULL;
static void                    *g_hidClient        = NULL;
static BOOL                     g_hidTried         = NO;

@implementation LKFIClicker

+ (void)loadSymbols
{
    if (g_hidTried) return;
    g_hidTried = YES;

    dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/IOKit.framework/IOKit", RTLD_NOW);

    g_fnClientCreate    = (LKFI_FnClientCreate)dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientCreate");
    g_fnDispatch        = (LKFI_FnDispatch)dlsym(RTLD_DEFAULT, "IOHIDEventSystemClientDispatchEvent");
    g_fnCreateDigitizer = (LKFI_FnCreateDigitizer)dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerEvent");
    g_fnCreateFinger    = (LKFI_FnCreateFinger)dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerFingerEvent");
    g_fnAppend          = (LKFI_FnAppend)dlsym(RTLD_DEFAULT, "IOHIDEventAppendEvent");
    g_fnSetInteger      = (LKFI_FnSetInteger)dlsym(RTLD_DEFAULT, "IOHIDEventSetIntegerValue");
    g_fnSetSender       = (LKFI_FnSetSender)dlsym(RTLD_DEFAULT, "IOHIDEventSetSenderID");

    if (g_fnClientCreate) g_hidClient = g_fnClientCreate(kCFAllocatorDefault);

    LKFI_LOG("hid client=%p finger=%p dispatch=%p",
             g_hidClient, (void *)g_fnCreateFinger, (void *)g_fnDispatch);
}

+ (BOOL)available
{
    [self loadSymbols];
    return (g_hidClient != NULL && g_fnDispatch != NULL &&
            g_fnCreateDigitizer != NULL && g_fnCreateFinger != NULL && g_fnAppend != NULL);
}

+ (BOOL)sendTouchAt:(CGPoint)p down:(BOOL)down
{
    [self loadSymbols];
    if (![self available]) return NO;

    uint64_t now = mach_absolute_time();

    // type = 3 (hand)，作为手指事件的容器
    void *hand = g_fnCreateDigitizer(kCFAllocatorDefault,   // allocator
                                     now,                   // timeStamp
                                     3,                     // transducerType: hand
                                     0,                     // index
                                     0,                     // identity
                                     0,                     // eventMask
                                     0,                     // buttonMask
                                     0, 0, 0,               // x, y, z
                                     0, 0,                  // tipPressure, twist
                                     0, 0,                  // range, touch
                                     0);                    // options
    if (!hand) return NO;

    void *finger = g_fnCreateFinger(kCFAllocatorDefault, now,
                                    1,      // index
                                    1,      // identity
                                    3,      // eventMask: range + touch
                                    (double)p.x, (double)p.y,
                                    0.0,    // z
                                    1.0,    // tipPressure
                                    0.0,    // twist
                                    1,      // range
                                    down ? 1 : 0,
                                    0);
    if (!finger) { CFRelease(hand); return NO; }

    g_fnAppend(hand, finger);
    CFRelease(finger);

    if (g_fnSetInteger) g_fnSetInteger(hand, 0x2A /* IsDisplayIntegrated */, 1);
    if (g_fnSetSender)  g_fnSetSender(hand, 0x8000000C00000002ULL);

    g_fnDispatch(g_hidClient, hand);
    CFRelease(hand);
    return YES;
}

+ (BOOL)tapAt:(CGPoint)point
{
    if (![self available]) {
        LKFI_LOG("tap: hid unavailable");
        return NO;
    }
    [self sendTouchAt:point down:YES];
    usleep(30000);
    [self sendTouchAt:point down:NO];
    return YES;
}

@end
