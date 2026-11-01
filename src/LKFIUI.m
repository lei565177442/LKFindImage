//
//  LKFIUI.m
//  框选器 / 命中可视化 / 主面板 / 悬浮球
//

#import "LKFICommon.h"
#import "LKFIMatcher.h"
#import <math.h>
#import <stdlib.h>

/* =====================================================================
 *  小工具
 * ===================================================================== */

static UILabel *LKFLabel(NSString *text, CGFloat size, BOOL bold, UIColor *color)
{
    UILabel *l = [[UILabel alloc] init];
    l.text = text;
    l.font = bold ? [UIFont boldSystemFontOfSize:size] : [UIFont systemFontOfSize:size];
    l.textColor = color ?: [UIColor labelColor];
    return l;
}

static UIButton *LKFSmallButton(NSString *title, id target, SEL action)
{
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    b.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    b.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    b.layer.cornerRadius = 8;
    b.contentEdgeInsets = UIEdgeInsetsMake(6, 12, 6, 12);
    [b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    [b.heightAnchor constraintEqualToConstant:32].active = YES;
    return b;
}

static UIStackView *LKFRow(NSArray<UIView *> *views, CGFloat spacing)
{
    UIStackView *s = [[UIStackView alloc] initWithArrangedSubviews:views];
    s.axis = UILayoutConstraintAxisHorizontal;
    s.alignment = UIStackViewAlignmentCenter;
    s.spacing = spacing;
    return s;
}

static UIView *LKFSpacer(void)
{
    UIView *v = [[UIView alloc] init];
    [v setContentHuggingPriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    [v setContentCompressionResistancePriority:1 forAxis:UILayoutConstraintAxisHorizontal];
    return v;
}

/* =====================================================================
 *  框选器
 * ===================================================================== */

@interface LKFISelectorView : UIView
@property (nonatomic, copy)   void (^onFinish)(CGRect rect, BOOL confirmed);
@property (nonatomic, strong) CAShapeLayer *shape;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) UILabel *sizeLabel;
@property (nonatomic, strong) UIButton *confirmBtn;
@property (nonatomic, assign) CGPoint startPoint;
@property (nonatomic, assign) CGRect  currentRect;
@property (nonatomic, assign) BOOL    dragging;
@end

@implementation LKFISelectorView

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.30];
        self.userInteractionEnabled = YES;

        _hintLabel = LKFLabel(@"拖动框选区域", 15, YES, [UIColor whiteColor]);
        _hintLabel.textAlignment = NSTextAlignmentCenter;
        _hintLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
        _hintLabel.layer.cornerRadius = 10;
        _hintLabel.clipsToBounds = YES;
        _hintLabel.frame = CGRectMake(0, 0, 260, 36);
        _hintLabel.center = CGPointMake(frame.size.width / 2, 84);
        [self addSubview:_hintLabel];

        _sizeLabel = LKFLabel(@"", 12, NO, [UIColor whiteColor]);
        _sizeLabel.textAlignment = NSTextAlignmentCenter;
        _sizeLabel.frame = CGRectMake(0, 0, 200, 18);
        _sizeLabel.center = CGPointMake(frame.size.width / 2, 108);
        [self addSubview:_sizeLabel];

        _shape = [CAShapeLayer layer];
        _shape.strokeColor = [UIColor colorWithRed:1 green:0.82 blue:0.1 alpha:1].CGColor;
        _shape.fillColor = [UIColor colorWithRed:1 green:0.82 blue:0.1 alpha:0.12].CGColor;
        _shape.lineWidth = 1.5;
        [self.layer addSublayer:_shape];

        CGFloat bottom = frame.size.height - 40;
        _confirmBtn = [UIButton buttonWithType:UIButtonTypeSystem];
        [_confirmBtn setTitle:@"完成" forState:UIControlStateNormal];
        [_confirmBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        _confirmBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        _confirmBtn.backgroundColor = [UIColor colorWithRed:0.1 green:0.55 blue:1 alpha:1];
        _confirmBtn.layer.cornerRadius = 22;
        _confirmBtn.frame = CGRectMake(frame.size.width / 2 - 110, bottom - 22, 100, 44);
        _confirmBtn.alpha = 0.4;
        _confirmBtn.enabled = NO;
        [_confirmBtn addTarget:self action:@selector(onConfirm) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_confirmBtn];

        UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
        [cancel setTitle:@"取消" forState:UIControlStateNormal];
        [cancel setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        cancel.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        cancel.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1];
        cancel.layer.cornerRadius = 22;
        cancel.frame = CGRectMake(frame.size.width / 2 + 10, bottom - 22, 100, 44);
        [cancel addTarget:self action:@selector(onCancel) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:cancel];

        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

- (void)onPan:(UIPanGestureRecognizer *)g
{
    CGPoint p = [g locationInView:self];
    if (g.state == UIGestureRecognizerStateBegan) {
        _startPoint = p;
        _dragging = YES;
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGFloat x0 = MIN(_startPoint.x, p.x);
        CGFloat y0 = MIN(_startPoint.y, p.y);
        CGFloat w  = fabs(p.x - _startPoint.x);
        CGFloat h  = fabs(p.y - _startPoint.y);
        _currentRect = CGRectMake(x0, y0, w, h);

        UIBezierPath *path = [UIBezierPath bezierPathWithRect:_currentRect];
        _shape.path = path.CGPath;
        _sizeLabel.text = [NSString stringWithFormat:@"%.0f × %.0f", w, h];

        BOOL ok = (w >= 8 && h >= 8);
        _confirmBtn.enabled = ok;
        _confirmBtn.alpha = ok ? 1.0 : 0.4;
    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled) {
        _dragging = NO;
    }
}

- (void)onConfirm
{
    if (self.onFinish) {
        CGRect r = _currentRect;
        if (r.size.width < 8 || r.size.height < 8) {
            self.onFinish(CGRectZero, NO);
        } else {
            self.onFinish(r, YES);
        }
    }
}

- (void)onCancel
{
    if (self.onFinish) self.onFinish(CGRectZero, NO);
}

@end

static UIWindow *gSelectorWindow = nil;

@implementation LKFISelector

+ (void)presentWithHint:(NSString *)hint
             completion:(void (^)(CGRect, BOOL))completion
{
    if (gSelectorWindow) return;

    UIWindow *win = [LKFIWindows newOverlayWindowAtLevel:UIWindowLevelAlert + 50];
    LKFISelectorView *v = [[LKFISelectorView alloc] initWithFrame:win.bounds];
    if (hint.length > 0) v.hintLabel.text = hint;

    v.onFinish = ^(CGRect rect, BOOL confirmed) {
        UIWindow *w = gSelectorWindow;
        gSelectorWindow = nil;
        w.hidden = YES;
        [LKFIWindows unregisterWindow:w];
        // 给系统一帧时间把框选层撤掉，再让调用方截屏
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.12 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (completion) completion(rect, confirmed);
        });
    };

    [win.rootViewController.view addSubview:v];
    gSelectorWindow = win;
    win.hidden = NO;
}

@end

/* =====================================================================
 *  命中框可视化
 * ===================================================================== */

@interface LKFIHitView : UIView
@property (nonatomic, strong) NSArray<NSValue *> *rects;
@property (nonatomic, strong) NSArray<NSNumber *> *scores;
@end

@implementation LKFIHitView

- (void)drawRect:(CGRect)rect
{
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;

    for (NSUInteger i = 0; i < self.rects.count; i++) {
        CGRect r = [self.rects[i] CGRectValue];
        UIColor *c = (i == 0)
            ? [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0]
            : [UIColor colorWithRed:0.1 green:0.85 blue:0.45 alpha:1.0];

        CGContextSetStrokeColorWithColor(ctx, c.CGColor);
        CGContextSetLineWidth(ctx, 2.0);
        CGContextStrokeRect(ctx, CGRectInset(r, -1, -1));

        double score = (i < self.scores.count) ? [self.scores[i] doubleValue] : 0.0;
        NSString *txt = [NSString stringWithFormat:@"%lu  %.2f", (unsigned long)(i + 1), score];
        NSDictionary *attrs = @{
            NSFontAttributeName: [UIFont boldSystemFontOfSize:11],
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSBackgroundColorAttributeName: c
        };
        CGSize sz = [txt sizeWithAttributes:attrs];
        CGRect tr = CGRectMake(r.origin.x, MAX(0, r.origin.y - sz.height - 2), sz.width + 8, sz.height);
        [txt drawInRect:tr withAttributes:attrs];
    }
}

@end

static UIWindow *gHitWindow = nil;

@implementation LKFIHitOverlay

+ (void)showRects:(NSArray<NSValue *> *)rects
           scores:(NSArray<NSNumber *> *)scores
         duration:(NSTimeInterval)duration
{
    [self clear];

    if (rects.count == 0) return;

    UIWindow *win = [LKFIWindows newOverlayWindowAtLevel:UIWindowLevelAlert + 10];
    win.userInteractionEnabled = NO;   // 整层不拦截触摸

    LKFIHitView *v = [[LKFIHitView alloc] initWithFrame:win.bounds];
    v.backgroundColor = [UIColor clearColor];
    v.opaque = NO;
    v.userInteractionEnabled = NO;
    v.rects = rects;
    v.scores = scores;
    [win.rootViewController.view addSubview:v];
    [v setNeedsDisplay];

    gHitWindow = win;

    if (duration <= 0) duration = 2.0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(duration * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [LKFIHitOverlay clear];
    });
}

+ (void)clear
{
    if (!gHitWindow) return;
    UIWindow *w = gHitWindow;
    gHitWindow = nil;
    w.hidden = YES;
    [LKFIWindows unregisterWindow:w];
}

@end

/* =====================================================================
 *  主面板
 * ===================================================================== */

@interface LKFIPanel ()
@property (nonatomic, strong) UIImage *templateImage;
@property (nonatomic, copy)   NSString *templateName;
@property (nonatomic, copy)   NSArray<NSValue *> *lastRects;
@property (nonatomic, copy)   NSArray<NSNumber *> *lastScores;
@end

@implementation LKFIPanel
{
    UIImageView *_thumb;
    UILabel     *_nameLabel;
    UILabel     *_sizeLabel;
    UILabel     *_regionValue;
    UILabel     *_thrValue;
    UILabel     *_strategyValue;
    UILabel     *_statusLabel;
    UISlider    *_thrSlider;
    UISwitch    *_swBox;
    UISwitch    *_swClick;
    UIButton    *_runBtn;
    UIButton    *_confirmBtn;

    CGRect       _region;      // 宿主窗口坐标（点），CGRectNull 表示全屏
    CGFloat      _threshold;
    LKFIStrategy _strategy;
    BOOL         _busy;
}

+ (instancetype)shared
{
    static LKFIPanel *panel = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CGRect sb = UIScreen.mainScreen.bounds;
        CGRect f = CGRectMake(0, 0, MIN(340, sb.size.width - 24), 468);

        UIWindow *win = [LKFIWindows newOverlayWindowAtLevel:UIWindowLevelAlert + 30];
        win.frame = f;

        panel = [[LKFIPanel alloc] initWithFrame:win.bounds];
        [win.rootViewController.view addSubview:panel];

        win.hidden = YES;
        panel.hidden = NO;
    });
    return panel;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        _threshold = 0.85;
        _strategy  = LKFIStrategyBestScore;
        _region    = CGRectNull;

        self.backgroundColor = [UIColor secondarySystemBackgroundColor];
        self.layer.cornerRadius = 16;
        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOpacity = 0.25;
        self.layer.shadowRadius = 10;
        self.layer.shadowOffset = CGSizeMake(0, 4);

        [self buildUI];
    }
    return self;
}

#pragma mark - UI 构建

- (void)buildUI
{
    // 标题行
    UILabel *title = LKFLabel(@"找图识别", 16, YES, [UIColor labelColor]);
    UILabel *ver = LKFLabel([NSString stringWithFormat:@"v%@", LKFI_VERSION], 11, NO, [UIColor secondaryLabelColor]);
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"收起" forState:UIControlStateNormal];
    close.titleLabel.font = [UIFont systemFontOfSize:13];
    [close addTarget:self action:@selector(onClose) forControlEvents:UIControlEventTouchUpInside];
    [close setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];

    UIStackView *titleRow = LKFRow(@[title, ver, LKFSpacer(), close], 6);

    // 模板行
    _thumb = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    _thumb.layer.cornerRadius = 8;
    _thumb.layer.borderWidth = 1;
    _thumb.layer.borderColor = [UIColor separatorColor].CGColor;
    _thumb.clipsToBounds = YES;
    _thumb.contentMode = UIViewContentModeScaleAspectFit;
    _thumb.backgroundColor = [UIColor tertiarySystemBackgroundColor];
    [_thumb.widthAnchor constraintEqualToConstant:44].active = YES;
    [_thumb.heightAnchor constraintEqualToConstant:44].active = YES;

    _nameLabel = LKFLabel(@"未取模板", 14, YES, [UIColor labelColor]);
    _sizeLabel = LKFLabel(@"先点右侧“取模板”", 11, NO, [UIColor secondaryLabelColor]);

    UIStackView *nameCol = [[UIStackView alloc] initWithArrangedSubviews:@[_nameLabel, _sizeLabel]];
    nameCol.axis = UILayoutConstraintAxisVertical;
    nameCol.spacing = 2;

    UIButton *takeBtn = LKFSmallButton(@"取模板", self, @selector(onTakeTemplate));
    UIButton *pickBtn = LKFSmallButton(@"选择", self, @selector(onPickTemplate));

    UIStackView *tplRow = LKFRow(@[_thumb, nameCol, LKFSpacer(), takeBtn, pickBtn], 8);

    // 区域行
    UILabel *regionTitle = LKFLabel(@"搜索区域", 13, NO, [UIColor secondaryLabelColor]);
    _regionValue = LKFLabel(@"全屏", 13, YES, [UIColor labelColor]);
    UIButton *regionBtn = LKFSmallButton(@"框选", self, @selector(onPickRegion));
    UIStackView *regionRow = LKFRow(@[regionTitle, _regionValue, LKFSpacer(), regionBtn], 8);

    // 相似度
    UILabel *thrTitle = LKFLabel(@"相似度", 13, NO, [UIColor secondaryLabelColor]);
    _thrSlider = [[UISlider alloc] init];
    _thrSlider.minimumValue = 0.50f;
    _thrSlider.maximumValue = 1.00f;
    _thrSlider.value = (float)_threshold;
    [_thrSlider addTarget:self action:@selector(onThresholdChanged:) forControlEvents:UIControlEventValueChanged];
    [_thrSlider setContentHuggingPriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    _thrValue = LKFLabel(@"0.85", 13, YES, [UIColor labelColor]);
    [_thrValue.widthAnchor constraintEqualToConstant:40].active = YES;
    UIStackView *thrRow = LKFRow(@[thrTitle, _thrSlider, _thrValue], 8);

    // 策略
    UILabel *stgTitle = LKFLabel(@"选取策略", 13, NO, [UIColor secondaryLabelColor]);
    _strategyValue = LKFLabel(@"最高分", 13, YES, [UIColor labelColor]);
    UIButton *stgBtn = LKFSmallButton(@"更改", self, @selector(onPickStrategy));
    UIStackView *stgRow = LKFRow(@[stgTitle, _strategyValue, LKFSpacer(), stgBtn], 8);

    // 开关
    _swBox = [[UISwitch alloc] init];
    _swBox.on = YES;
    UIStackView *boxRow = LKFRow(@[LKFLabel(@"命中框可视化", 13, NO, [UIColor labelColor]), LKFSpacer(), _swBox], 8);

    _swClick = [[UISwitch alloc] init];
    _swClick.on = NO;
    UILabel *clickHint = LKFLabel(@"自动点击(需HID权限)", 11, NO, [UIColor secondaryLabelColor]);
    UIStackView *clickCol = [[UIStackView alloc] initWithArrangedSubviews:
                              @[LKFLabel(@"命中后自动点击", 13, NO, [UIColor labelColor]), clickHint]];
    clickCol.axis = UILayoutConstraintAxisVertical;
    clickCol.spacing = 1;
    UIStackView *clickRow = LKFRow(@[clickCol, LKFSpacer(), _swClick], 8);

    // 主按钮
    _runBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    [_runBtn setTitle:@"识 别 一 次" forState:UIControlStateNormal];
    [_runBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _runBtn.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    _runBtn.backgroundColor = [UIColor colorWithRed:0.10 green:0.53 blue:1.0 alpha:1.0];
    _runBtn.layer.cornerRadius = 10;
    [_runBtn.heightAnchor constraintEqualToConstant:44].active = YES;
    [_runBtn addTarget:self action:@selector(onRun) forControlEvents:UIControlEventTouchUpInside];

    // 状态
    _statusLabel = LKFLabel(@"等待操作", 12, NO, [UIColor secondaryLabelColor]);
    _statusLabel.numberOfLines = 0;

    // 底部
    _confirmBtn = LKFSmallButton(@"复制坐标", self, @selector(onCopyCoord));
    UIButton *listBtn = LKFSmallButton(@"全部命中", self, @selector(onShowAllHits));
    UIStackView *footRow = LKFRow(@[_confirmBtn, listBtn, LKFSpacer()], 8);

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:
                          @[titleRow, tplRow, regionRow, thrRow, stgRow, boxRow, clickRow, _runBtn, _statusLabel, footRow]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 9;
    stack.alignment = UIStackViewAlignmentFill;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];

    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor constant:14],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-14]
    ]];
}

#pragma mark - 显示控制

- (void)show
{
    UIWindow *w = self.window;
    if (!w) return;
    w.hidden = NO;
}

- (void)hide
{
    self.window.hidden = YES;
}

- (BOOL)isShown
{
    return self.window != nil && !self.window.hidden;
}

- (void)onClose
{
    [self hide];
}

#pragma mark - 模板

- (void)refreshTemplateRow
{
    _thumb.image = self.templateImage;
    _nameLabel.text = self.templateName.length ? self.templateName : @"未取模板";
    if (self.templateImage.CGImage) {
        _sizeLabel.text = [NSString stringWithFormat:@"%zupx × %zupx",
                           CGImageGetWidth(self.templateImage.CGImage),
                           CGImageGetHeight(self.templateImage.CGImage)];
    }
}

- (void)onTakeTemplate
{
    __weak typeof(self) weakSelf = self;
    BOOL wasShown = [self isShown];
    [self hide];

    [LKFISelector presentWithHint:@"框选要识别的图标/按钮（越小越准）"
                       completion:^(CGRect rect, BOOL confirmed) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (!confirmed || rect.size.width < 6 || rect.size.height < 6) {
            if (wasShown) [self show];
            return;
        }

        UIImage *shot = [LKFICapture captureHostWindow];
        if (!shot) {
            [self setStatus:@"截屏失败"];
            if (wasShown) [self show];
            return;
        }

        CGFloat s = shot.scale > 0 ? shot.scale : UIScreen.mainScreen.scale;
        CGRect pixelRect = CGRectMake(rect.origin.x * s, rect.origin.y * s,
                                      rect.size.width * s, rect.size.height * s);
        UIImage *tpl = [LKFIImageUtil cropImage:shot toPixelRect:pixelRect];
        if (!tpl) {
            [self setStatus:@"取模板失败：区域太小"];
            if (wasShown) [self show];
            return;
        }

        LKFITemplateStore *store = [LKFITemplateStore shared];
        NSString *name = [store nextTemplateName];
        LKFITemplate *saved = [store saveImage:tpl name:name];

        self.templateImage = tpl;
        self.templateName = saved.name ?: name;
        [self refreshTemplateRow];
        [self setStatus:[NSString stringWithFormat:@"模板已保存：%@", self.templateName]];

        if (wasShown) [self show];
    }];
}

- (void)onPickTemplate
{
    NSArray<LKFITemplate *> *all = [[LKFITemplateStore shared] allTemplates];
    if (all.count == 0) {
        [self setStatus:@"还没有保存过模板"];
        return;
    }

    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选择模板"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (LKFITemplate *t in all) {
        [sheet addAction:[UIAlertAction actionWithTitle:t.name
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            UIImage *img = [[LKFITemplateStore shared] imageForTemplate:t];
            if (!img) { [self setStatus:@"模板文件丢失"]; return; }
            self.templateImage = img;
            self.templateName = t.name;
            [self refreshTemplateRow];
            [self setStatus:[NSString stringWithFormat:@"已选择：%@", t.name]];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

    [self presentSheet:sheet];
}

- (void)presentSheet:(UIAlertController *)vc
{
    UIViewController *root = self.window.rootViewController;
    if (!root) return;

    if (@available(iOS 13.0, *)) {
        vc.modalPresentationStyle = UIModalPresentationPopover;
        vc.popoverPresentationController.sourceView = self;
        vc.popoverPresentationController.sourceRect = CGRectMake(self.bounds.size.width / 2,
                                                                 self.bounds.size.height / 2, 1, 1);
        vc.popoverPresentationController.permittedArrowDirections = 0;
    }
    [root presentViewController:vc animated:YES completion:nil];
}

#pragma mark - 区域 / 阈值 / 策略

- (void)refreshRegionLabel
{
    if (CGRectIsNull(_region)) {
        _regionValue.text = @"全屏";
    } else {
        _regionValue.text = [NSString stringWithFormat:@"%.0f,%.0f %.0f×%.0f",
                             _region.origin.x, _region.origin.y,
                             _region.size.width, _region.size.height];
    }
}

- (void)onPickRegion
{
    __weak typeof(self) weakSelf = self;
    BOOL wasShown = [self isShown];
    [self hide];

    [LKFISelector presentWithHint:@"框选搜索区域（只在这块里找图）"
                       completion:^(CGRect rect, BOOL confirmed) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

        if (!confirmed || rect.size.width < 8 || rect.size.height < 8) {
            if (wasShown) [self show];
            return;
        }
        self->_region = rect;
        [self refreshRegionLabel];
        [self setStatus:@"搜索区域已设置"];
        if (wasShown) [self show];
    }];
}

- (void)onThresholdChanged:(UISlider *)s
{
    _threshold = s.value;
    _thrValue.text = [NSString stringWithFormat:@"%.2f", _threshold];
}

- (void)onPickStrategy
{
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"选取策略"
                                                                   message:@"多个命中时选哪个作为结果"
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    for (NSInteger i = LKFIStrategyBestScore; i <= LKFIStrategyRandom; i++) {
        NSString *name = LKFIStrategyName((LKFIStrategy)i);
        [sheet addAction:[UIAlertAction actionWithTitle:name
                                                  style:UIAlertActionStyleDefault
                                                handler:^(UIAlertAction *a) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self->_strategy = (LKFIStrategy)i;
            self->_strategyValue.text = name;
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentSheet:sheet];
}

#pragma mark - 识别

- (void)setStatus:(NSString *)text
{
    dispatch_async(dispatch_get_main_queue(), ^{
        self->_statusLabel.text = text;
    });
}

- (void)onRun
{
    [self runOnce];
}

- (void)runOnce
{
    if (_busy) return;

    if (!self.templateImage) {
        [self setStatus:@"请先取模板：点“取模板”后在屏幕上框选目标"];
        return;
    }

    _busy = YES;
    [self setStatus:@"识别中…"];

    // 让状态文字先刷新出来
    dispatch_async(dispatch_get_main_queue(), ^{
        [self doMatch];
    });
}

- (void)doMatch
{
    NSDate *t0 = [NSDate date];

    UIImage *shot = [LKFICapture captureHostWindow];
    if (!shot || !shot.CGImage) {
        _busy = NO;
        [self setStatus:@"截屏失败：未找到宿主窗口"];
        return;
    }

    CGFloat scale = shot.scale > 0 ? shot.scale : UIScreen.mainScreen.scale;
    CGFloat imgW = (CGFloat)CGImageGetWidth(shot.CGImage);
    CGFloat imgH = (CGFloat)CGImageGetHeight(shot.CGImage);

    CGRect regionPts = _region;
    if (CGRectIsNull(regionPts) || regionPts.size.width < 8 || regionPts.size.height < 8) {
        regionPts = CGRectMake(0, 0, imgW / scale, imgH / scale);
    }

    CGRect pixelRect = CGRectMake(regionPts.origin.x * scale, regionPts.origin.y * scale,
                                  regionPts.size.width * scale, regionPts.size.height * scale);
    pixelRect = CGRectIntegral(CGRectIntersection(pixelRect, CGRectMake(0, 0, imgW, imgH)));

    UIImage *regionImg = [LKFIImageUtil cropImage:shot toPixelRect:pixelRect];
    if (!regionImg.CGImage) {
        _busy = NO;
        [self setStatus:@"截取搜索区域失败"];
        return;
    }

    int rw = 0, rh = 0, tw = 0, th = 0;
    uint8_t *rg = [LKFIImageUtil grayCopyOfCGImage:regionImg.CGImage width:&rw height:&rh];
    uint8_t *tg = [LKFIImageUtil grayCopyOfCGImage:self.templateImage.CGImage width:&tw height:&th];

    if (!rg || !tg) {
        free(rg);
        free(tg);
        _busy = NO;
        [self setStatus:@"灰度转换失败"];
        return;
    }

    if (tw >= rw || th >= rh) {
        free(rg);
        free(tg);
        _busy = NO;
        [self setStatus:@"模板比搜索区域还大，请缩小模板或扩大区域"];
        return;
    }

    LKFIHit hits[64];
    int n = lkfi_match(rg, rw, rh, tg, tw, th,
                       (float)_threshold, 64, 0.0f, hits, 64);

    free(rg);
    free(tg);

    NSMutableArray<NSValue *> *rects = [NSMutableArray array];
    NSMutableArray<NSNumber *> *scores = [NSMutableArray array];

    for (int i = 0; i < n; i++) {
        CGRect hr = CGRectMake((pixelRect.origin.x + hits[i].x) / scale,
                               (pixelRect.origin.y + hits[i].y) / scale,
                               hits[i].w / scale,
                               hits[i].h / scale);
        [rects addObject:[NSValue valueWithCGRect:hr]];
        [scores addObject:@(hits[i].score)];
    }

    NSTimeInterval cost = -[t0 timeIntervalSinceNow];
    self.lastRects = rects;
    self.lastScores = scores;

    if (n == 0) {
        _busy = NO;
        [LKFIHitOverlay clear];
        [self setStatus:[NSString stringWithFormat:@"没找到（阈值 %.2f，用时 %.0fms）\n可试试降低相似度或缩小搜索区域",
                         _threshold, cost * 1000.0]];
        return;
    }

    NSInteger idx = [self pickIndexFrom:rects scores:scores];
    CGRect chosen = [rects[idx] CGRectValue];
    CGPoint pt = CGPointMake(CGRectGetMidX(chosen), CGRectGetMidY(chosen));

    if (_swBox.on) {
        [LKFIHitOverlay showRects:rects scores:scores duration:2.5];
    } else {
        [LKFIHitOverlay clear];
    }

    NSMutableString *msg = [NSMutableString string];
    [msg appendFormat:@"命中 %d 个 · 用时 %.0fms\n", n, cost * 1000.0];
    NSInteger showCount = MIN((NSInteger)rects.count, 3);
    for (NSInteger i = 0; i < showCount; i++) {
        CGRect r = [rects[i] CGRectValue];
        [msg appendFormat:@"%ld) (%.0f, %.0f)  %.2f%@\n",
         (long)(i + 1), CGRectGetMidX(r), CGRectGetMidY(r),
         [scores[i] doubleValue], (i == idx ? @"  ←选中" : @"")];
    }
    if (rects.count > showCount) [msg appendString:@"…"];
    [self setStatus:msg];

    CGPoint screenPt = pt;

    if (_swClick.on) {
        BOOL ok = [LKFIClicker tapAt:screenPt];
        if (!ok) [self setStatus:[msg stringByAppendingString:@"\n自动点击不可用（缺 HID 权限），可复制坐标手动用"]];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:LKFI_HIT_NOTIFICATION
                                                        object:self
                                                      userInfo:@{
        @"hits": rects,
        @"scores": scores,
        @"index": @(idx),
        @"x": @(screenPt.x),
        @"y": @(screenPt.y)
    }];

    _busy = NO;
}

- (NSInteger)pickIndexFrom:(NSArray<NSValue *> *)rects scores:(NSArray<NSNumber *> *)scores
{
    if (rects.count == 0) return -1;
    NSInteger best = 0;

    switch (_strategy) {
        case LKFIStrategyBestScore: {
            double bs = -2.0;
            for (NSUInteger i = 0; i < scores.count; i++) {
                double s = [scores[i] doubleValue];
                if (s > bs) { bs = s; best = (NSInteger)i; }
            }
            break;
        }
        case LKFIStrategyLeftmost: {
            CGFloat v = CGFLOAT_MAX;
            for (NSUInteger i = 0; i < rects.count; i++) {
                CGFloat x = [rects[i] CGRectValue].origin.x;
                if (x < v) { v = x; best = (NSInteger)i; }
            }
            break;
        }
        case LKFIStrategyTopmost: {
            CGFloat v = CGFLOAT_MAX;
            for (NSUInteger i = 0; i < rects.count; i++) {
                CGFloat y = [rects[i] CGRectValue].origin.y;
                if (y < v) { v = y; best = (NSInteger)i; }
            }
            break;
        }
        case LKFIStrategyRightmost: {
            CGFloat v = -CGFLOAT_MAX;
            for (NSUInteger i = 0; i < rects.count; i++) {
                CGFloat x = CGRectGetMaxX([rects[i] CGRectValue]);
                if (x > v) { v = x; best = (NSInteger)i; }
            }
            break;
        }
        case LKFIStrategyBottommost: {
            CGFloat v = -CGFLOAT_MAX;
            for (NSUInteger i = 0; i < rects.count; i++) {
                CGFloat y = CGRectGetMaxY([rects[i] CGRectValue]);
                if (y > v) { v = y; best = (NSInteger)i; }
            }
            break;
        }
        case LKFIStrategyRandom: {
            if (rects.count > 1) best = (NSInteger)arc4random_uniform((uint32_t)rects.count);
            break;
        }
    }
    return best;
}

#pragma mark - 输出

- (void)onCopyCoord
{
    if (self.lastRects.count == 0) {
        [self setStatus:@"还没有识别结果"];
        return;
    }
    NSInteger idx = [self pickIndexFrom:self.lastRects scores:self.lastScores];
    if (idx < 0) return;

    CGRect r = [self.lastRects[idx] CGRectValue];
    NSString *s = [NSString stringWithFormat:@"%.1f,%.1f", CGRectGetMidX(r), CGRectGetMidY(r)];
    [UIPasteboard generalPasteboard].string = s;
    [self setStatus:[NSString stringWithFormat:@"已复制：%@", s]];
}

- (void)onShowAllHits
{
    if (self.lastRects.count == 0) {
        [self setStatus:@"还没有识别结果"];
        return;
    }
    NSMutableString *msg = [NSMutableString stringWithFormat:@"共 %lu 个命中：\n", (unsigned long)self.lastRects.count];
    for (NSUInteger i = 0; i < self.lastRects.count; i++) {
        CGRect r = [self.lastRects[i] CGRectValue];
        [msg appendFormat:@"%lu) %.0f,%.0f  %.2f\n", (unsigned long)(i + 1),
         CGRectGetMidX(r), CGRectGetMidY(r), [self.lastScores[i] doubleValue]];
    }
    [self setStatus:msg];
}

@end

/* =====================================================================
 *  悬浮球
 * ===================================================================== */

@implementation LKFIFloatBall
{
    CGPoint _panStartCenter;
}

- (instancetype)initWithFrame:(CGRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor colorWithWhite:0.10 alpha:0.72];
        self.layer.cornerRadius = frame.size.width / 2.0;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
        self.userInteractionEnabled = YES;

        UILabel *l = LKFLabel(@"识", 20, YES, [UIColor whiteColor]);
        l.textAlignment = NSTextAlignmentCenter;
        l.frame = self.bounds;
        l.userInteractionEnabled = NO;
        [self addSubview:l];

        [self addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(onTap)]];
        [self addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)]];
        [self addGestureRecognizer:[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(onLongPress:)]];
    }
    return self;
}

- (void)onTap
{
    LKFIPanel *p = [LKFIPanel shared];
    if ([p isShown]) [p hide];
    else {
        [self snapPanelNearBall];
        [p show];
    }
}

- (void)snapPanelNearBall
{
    LKFIPanel *p = [LKFIPanel shared];
    UIWindow *pw = p.window;
    if (!pw) return;

    CGRect sb = UIScreen.mainScreen.bounds;
    CGPoint c = self.window.center;
    CGFloat x = c.x < sb.size.width / 2 ? 8 : sb.size.width - pw.bounds.size.width - 8;
    CGFloat y = c.y - pw.bounds.size.height / 2;
    y = MAX(60, MIN(y, sb.size.height - pw.bounds.size.height - 40));
    pw.frame = CGRectMake(x, y, pw.bounds.size.width, pw.bounds.size.height);
}

- (void)onPan:(UIPanGestureRecognizer *)g
{
    UIWindow *w = self.window;
    if (!w) return;

    if (g.state == UIGestureRecognizerStateBegan) {
        _panStartCenter = w.center;
    } else if (g.state == UIGestureRecognizerStateChanged) {
        CGPoint d = [g translationInView:w];
        w.center = CGPointMake(_panStartCenter.x + d.x, _panStartCenter.y + d.y);
    } else if (g.state == UIGestureRecognizerStateEnded ||
               g.state == UIGestureRecognizerStateCancelled) {
        CGRect sb = UIScreen.mainScreen.bounds;
        CGFloat halfW = w.bounds.size.width / 2.0;
        CGFloat halfH = w.bounds.size.height / 2.0;
        CGFloat x = MIN(MAX(w.center.x, halfW + 4), sb.size.width - halfW - 4);
        CGFloat y = MIN(MAX(w.center.y, halfH + 40), sb.size.height - halfH - 40);
        [UIView animateWithDuration:0.2 animations:^{
            CGRect f = w.frame;
            f.origin.x = x - halfW;
            f.origin.y = y - halfH;
            w.frame = f;
        }];
    }
}

- (void)onLongPress:(UILongPressGestureRecognizer *)g
{
    if (g.state != UIGestureRecognizerStateBegan) return;
    [[LKFIPanel shared] runOnce];
}

@end
