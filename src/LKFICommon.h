//
//  LKFICommon.h
//  公共定义与各模块接口
//

#ifndef LKFICommon_h
#define LKFICommon_h

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

#define LKFI_LOG(...) NSLog(@"[LKFindImage] " __VA_ARGS__)
#define LKFI_VERSION @"1.0.0"

/// 识别完成时广播，userInfo 里带 hits / x / y / score，方便其它脚本或插件消费
#define LKFI_HIT_NOTIFICATION @"LKFIHitNotification"

typedef NS_ENUM(NSInteger, LKFIStrategy) {
    LKFIStrategyBestScore = 0,   // 最高分
    LKFIStrategyLeftmost,        // 最左
    LKFIStrategyTopmost,         // 最上
    LKFIStrategyRightmost,       // 最右
    LKFIStrategyBottommost,      // 最下
    LKFIStrategyRandom           // 随机一个
};

UIKIT_EXTERN NSString *LKFIStrategyName(LKFIStrategy s);

/* ============ 窗口管理 ============ */

@interface LKFIOverlayWindow : UIWindow
@end

@interface LKFIWindows : NSObject

+ (void)ensureSetup;

+ (void)registerWindow:(UIWindow *)w;
+ (void)unregisterWindow:(UIWindow *)w;
+ (NSArray<UIWindow *> *)ourWindows;

/// 隐藏我们所有悬浮层，返回“原本可见”的那批，供 restoreOurs: 还原
+ (NSArray<UIWindow *> *)hideOurs;
+ (void)restoreOurs:(NSArray<UIWindow *> *)wins;

/// 宿主 App 的窗口（不是我们自己的悬浮层）
+ (UIWindow *)hostWindow;

+ (UIWindow *)newOverlayWindowAtLevel:(UIWindowLevel)level;

@end

/* ============ 图像工具 ============ */

@interface LKFIImageUtil : NSObject

/// 按像素矩形裁剪（原点在左上角）
+ (UIImage *)cropImage:(UIImage *)img toPixelRect:(CGRect)r;

/// 转灰度缓冲，返回 malloc 的内存，调用方负责 free
+ (uint8_t *)grayCopyOfCGImage:(CGImageRef)cg width:(int *)ow height:(int *)oh;

@end

/* ============ 截屏 ============ */

@interface LKFICapture : NSObject

/// 截宿主窗口（截之前自动隐藏我们自己的所有悬浮层），返回 scale 为屏幕 scale 的图
+ (UIImage *)captureHostWindow;

@end

/* ============ 模板存储 ============ */

@interface LKFITemplate : NSObject
@property (nonatomic, copy)   NSString *name;
@property (nonatomic, copy)   NSString *path;
@property (nonatomic, assign) CGSize    pixelSize;
@end

@interface LKFITemplateStore : NSObject

+ (instancetype)shared;

- (NSArray<LKFITemplate *> *)allTemplates;
- (LKFITemplate *)saveImage:(UIImage *)image name:(NSString *)name;
- (void)removeTemplate:(LKFITemplate *)tpl;
- (UIImage *)imageForTemplate:(LKFITemplate *)tpl;
- (NSString *)nextTemplateName;

@end

/* ============ 点击注入（实验性） ============ */

@interface LKFIClicker : NSObject
+ (BOOL)available;
+ (BOOL)tapAt:(CGPoint)point;
@end

/* ============ 区域框选 ============ */

@interface LKFISelector : NSObject

+ (void)presentWithHint:(NSString *)hint
             completion:(void (^)(CGRect rectInPoints, BOOL confirmed))completion;

@end

/* ============ 命中框可视化 ============ */

@interface LKFIHitOverlay : NSObject

/// rects / scores 一一对应，rect 为宿主窗口坐标系（点）
+ (void)showRects:(NSArray<NSValue *> *)rects
           scores:(NSArray<NSNumber *> *)scores
         duration:(NSTimeInterval)duration;

+ (void)clear;

@end

/* ============ 主面板 ============ */

@interface LKFIPanel : UIView

+ (instancetype)shared;
- (void)show;
- (void)hide;
- (BOOL)isShown;
- (void)runOnce;

@end

/* ============ 悬浮球 ============ */

@interface LKFIFloatBall : UIView
@end

#endif /* LKFICommon_h */
