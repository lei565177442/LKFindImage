# LKFindImage — 区域找图识别（伴生插件）

给「老贝贝连点器 v5.0」做的**外挂式伴生插件**：不改原 dylib、不依赖它的 `常青.dylib`，自己挂一个悬浮球，
提供「在框选区域内识别指定图片」的完整能力，并补上原版缺的四件事。

## 与老贝贝连点器 v5.0 的差异

原版其实已有「框选区域 + 模板匹配」（OpenCV `matchTemplate` + `minMaxLoc`，模板只能从相册选，命中只取第一个）。
本插件补齐：

| 增量 | 说明 |
|---|---|
| 屏幕直接取模板 | 在画面上拖一个小框直接变成模板，不用先截图存相册 |
| 多命中与选取策略 | 返回全部命中，按 最高分/最左/最上/最右/最下/随机 选一个 |
| 命中框可视化 | 屏幕上画出命中框 + 相似度分数，调阈值不用盲猜 |
| 结果可输出 | 复制坐标到剪贴板；广播 `LKFIHitNotification` 供别的插件/脚本取用 |

## 结构

```
src/LKFIMatcher.c    灰度模板匹配：NCC + 积分图 + 4/8 倍降采样金字塔 + 全分辨率精修 + NMS
src/LKFISupport.m    窗口管理 / 截屏 / 灰度转换 / 模板存储 / IOHID 点击注入
src/LKFIUI.m         框选器 / 命中框 / 主面板 / 悬浮球
src/LKFIEntry.m      入口 constructor
build.sh             直接调 clang 出 dylib（无需 Theos）
.github/workflows    GitHub Actions 云编译
```

匹配算法不依赖 OpenCV，编译产物约 100KB 级，纯 C 实现：

1. 灰度化 → 4 倍（大区域 8 倍）降采样做粗搜，积分图 O(1) 求窗口均值/方差
2. 取粗搜前 48 个候选，回到全分辨率在 ±d 邻域精修
3. 按分数排序 + 距离 NMS，输出最多 64 个命中

## 构建

**方式一：GitHub Actions（推荐）**
推送到仓库 → Actions 自动跑 `build.sh` → 在 Artifacts 下载 `LKFindImage-dylib`。

**方式二：本地 macOS**
```bash
xcodebuild -version          # 需要装 Xcode
chmod +x build.sh && ./build.sh
```

产物：`LKFindImage.dylib`（arm64，iOS 14.0+，install_name `@executable_path/Frameworks/LKFindImage.dylib`）

## 安装（TrollStore / 巨魔）

1. 用 **TrollFools（巨魔版）** 或 ESign / Sideloadly 把 `LKFindImage.dylib` 注入到**你要连点的那个 App**
   （原版连点器也是被注入到目标 App 里工作的，两者可以注入到同一个 App）
2. 重新安装注入后的 App
3. 打开 App，屏幕右侧会出现「识」字悬浮球

> 说明：注入工具会往 App 的主程序加一条 `LC_LOAD_DYLIB`，并把 dylib 放进 `Frameworks/`。
> 如果你的注入工具要求不同的 install_name，改 `build.sh` 里那行即可。

## 使用

| 动作 | 效果 |
|---|---|
| 点悬浮球 | 打开/收起面板（面板会贴着球弹出） |
| 拖悬浮球 | 移动，松手自动吸附屏幕边缘 |
| 长按悬浮球 | 直接识别一次（用上次的模板和区域） |

面板流程：**取模板 →（可选）框选搜索区域 → 调相似度 → 识别一次**。

- **取模板**：点一下后在屏幕上拖一个框，框里就是模板（越小越准，别把会变化的内容框进去）
- **选择**：从已保存的模板里切换（模板存 App 沙盒 `Documents/LKFindImage/templates`）
- **搜索区域**：只在框选范围内找，能显著提速并减少误命中
- **相似度**：默认 0.85，静态图标 0.85~0.92 合适；有轻微动画/压缩的图往下调到 0.75~0.82
- **选取策略**：命中多个时选哪个作为结果
- **自动点击**：命中后直接点选中的位置（见下方限制）
- **复制坐标**：把选中命中的中心点复制成 `x,y`

## 已知限制

- **自动点击是实验性的**：走私有 `IOHIDEvent` 注入，要求宿主 App 的签名带
  `com.apple.private.hid.client.event-dispatch` 权限。TrollStore 可以给 IPA 伪造任意 entitlements，
  需要在签名工具里手动加上这两条才有效；没有权限时插件不会崩，只是点了没反应，会提示「自动点击不可用」。
- 只做**同分辨率**匹配，不做旋转/缩放容差（模板和屏幕必须同一比例，本插件取模板时天然满足）。
- 截屏方式与老贝贝连点器一致：`drawViewHierarchyInRect:afterScreenUpdates:`，**只能截到当前进程的 App 窗口**，
  截不到系统弹窗、键盘等独立窗口。
- 匹配在调用线程（主线程）算，整屏 + 大模板大约 200~600ms，有卡顿感属正常；缩小搜索区域可明显加快。

## 输出接口（给其它插件/脚本用）

```objc
[[NSNotificationCenter defaultCenter] addObserverForName:@"LKFIHitNotification"
                                                  object:nil
                                                   queue:[NSOperationQueue mainQueue]
                                              usingBlock:^(NSNotification *n) {
    NSArray *rects   = n.userInfo[@"hits"];     // NSValue(CGRect)，点坐标
    NSArray *scores  = n.userInfo[@"scores"];   // NSNumber(double)
    NSNumber *x      = n.userInfo[@"x"];        // 选中命中中心点
    NSNumber *y      = n.userInfo[@"y"];
    NSNumber *index  = n.userInfo[@"index"];
}];
```
