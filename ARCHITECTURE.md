# LaiCuiBa

BieCuiLe 1.0.6 (Windows) 的 Flutter 重建版。目标不是"抄一份源码"，而是做一个自己
能长期维护、并且把原版反复出现的播放 bug 从设计上规避掉的等价软件。

工程标识：目录与产品名 `LaiCuiBa`，Dart 包名 `lai_cui_ba`（Dart 只允许小写下划线，
故 import 路径为 `package:lai_cui_ba/...`），可执行文件 `LaiCuiBa.exe`。
代码内前缀统一为 `Lcb`（`LcbColors`、`LcbText`、`LcbPage`…）。

## 一、复刻的性质（先读这一段）

原版是 Flutter AOT 编译产物（`data/app.so`，17MB），**不可反编译成 Dart 源码**。
能拿到的只有：232 个源文件路径、类/方法/私有字段符号名、字符串常量、资源包。
所以本工程是"按界面与行为重新实现"，任何声称"还原原版代码"的做法都是假的。

已提取的资产（存于 `.probe/`）：

| 资产 | 文件 | 用途 |
| --- | --- | --- |
| 源文件清单（232 条） | `bcl106-dart-files.txt` | 模块划分依据 |
| 首页基准截图 | `bcl106-home.bmp` | 像素级对照 |
| 设置页截图 | `bcl106-settings.bmp` | 设置项结构 |
| 主题色采样 | — | `lib/core/theme.dart` 的 token |
| 标题字体 | `assets/fonts/LcbSerif-SemiBold.otf` | OFL 授权，可合法使用 |

## 二、已完成（Phase 0）

可运行、可对照的界面骨架，Windows 下 `flutter build windows` 直接出包。

- 无边框窗口 + 自绘标题栏（`— □ ×`、拖拽、双击最大化）
- Material 3 亮色主题，色值取自原版采样
- 左侧分组导航：媒体库 / 来源 / 列表 / 其他
- 顶栏：页面标题 + 源选择 chip + 搜索框（Ctrl K 提示）
- 首页：深色模糊海报 hero（自动轮播 + 分页点）、继续观看横版卡、分区竖版卡
- 资源 / 收藏 / 历史 / 设置四个页面的结构骨架

已知与原版的像素级差异：hero 高度按 396 取值，原版随窗口宽度自适应；分区卡片
宽度暂定 112。后续对照截图再收敛。

## 三、目录结构

```
lib/
  main.dart              无边框窗口初始化 + 应用入口
  core/
    theme.dart           颜色 / 字号 / 间距 token
    detail_nav.dart      LcbDetailScope：任何页面把详情页推给 shell
    search_state.dart    LcbSearch：搜索模式的开关 / 输入 / 严格 / 选源 + scope
  models/models.dart     MediaItem / SiteInfo / SourceInfo / HistoryEntry …
  services/
    store.dart           AppStore：源与站点的唯一真相源 + sitesForSelection()
    site_parser.dart     TVBox / catvod 配置 -> SiteInfo（纯本地 JSON）
    demo_data.dart       演示片单 + detailDemo 详情夹具
    search.dart          搜索结果模型 + searchCatalogue()（按站点 fan-out）
  ui/
    shell.dart           侧栏 + 顶栏 + 页面切换（含详情页 / 搜索态顶栏）
    pages/detail_page.dart 详情页（hero / 选集 / 演员阵容 / 分类）
    pages/search_page.dart 搜索页（空态 / 联想 / 结果）
    pages/common_pages.dart 资源 / 收藏 / 历史页
    widgets/search_sources_dialog.dart 「搜索哪些资源」源选择弹窗
    widgets/source_dialogs.dart 添加 / 编辑 / 删除源
    widgets/             hero_banner / media_card / poster_art / manage_folders_sheet
```

`PosterArt` 是占位海报（渐变 + 纹理 + 片名），接口上预留了换成真实封面的位置。

## 四、阶段规划

### Phase 1 — 数据层与页面闭环
本地存储（收藏/历史/设置）、`MediaItem` 从源适配器返回、详情页、搜索结果页、
收藏与历史页接真实数据。这一阶段结束时不联网也能把界面点通。

**已完成**：数据层闭环、设置持久化、收藏夹 CRUD、详情页（见下节）。
**未做**：搜索结果页；详情页的换平台/下载/追更/评论与选集筛选需要源数据。

#### 详情页（tvbox_detail_page 的等价物）

结构：整幅模糊海报背景带（高 386）+ 204×306 海报 + 标题块，往下依次是
选集（页签 + 集号网格）、演员阵容（72 圆头像横滑）、分类（灰胶囊）。
从历史、收藏、首页卡片、hero「详情」都能进入；顶栏换成「返回圆钮 + 片名」，
搜索框隐藏，侧栏选中态保持，返回时回到原页面。

| 项 | 实测（measure.py 截图坐标） |
| --- | --- |
| 背景带 | y 53–439，高 386；底部 120px 白色渐变 |
| 海报 | x 264–467（204 宽）× y 88–394（306 高），圆角 14 |
| 文案列 | x 500 起 |
| 标题 | 34px w700 白，墨迹 y 150–180 |
| 属性标签 | 高 26，圆角 6，白 10% 填充 + 白 20% 描边，文字 12.5 |
| 简介 | 13px，行高 1.62，**最大宽 845**（不是整幅宽），最多 2 行 |
| 按钮行 | 高 42，圆角 21，间距 13；主按钮 primaryDim 实色 |
| 选集标题 | 20px w700，墨迹 y 473–490；右侧筛选胶囊高 32 |
| 集号页签 | 高 36，圆角 12；选中 primaryDim + 白字 |
| 集号 chip | 高 44，圆角 12，#EFEFEF；选中 #EDEBF5 + primaryDim 字 |
| 每行集数 | 按可用宽算：`(W + 9) ~/ (92 + 9)`，1920 下 16 个，间距 9/10 |
| 演员头像 | 直径 72，间距 18，名字 12.5 w600 居中 |
| 分类 chip | 高 34，圆角 9，#F2F2F2，14px |

`选集` 分页每 20 集一页（1-20 / 21-40），进页面时定位到上次观看的那一页，
该集 chip 高亮。无集数（电影）时整段隐藏，主按钮文案退回「播放」。

#### 搜索页（顶栏展开 + 空态 + 联想 + 结果）

四种状态，由 `LcbSearch`（`lib/core/search_state.dart`）一个对象驱动：顶栏输入框和
内容列结果共用它，所以走 InheritedNotifier 而不是层层传参。

1. **未输入**：居中的放大镜 + 「搜索影视」+ 「会同时搜索影视源里的全部站点，结果按平台分组。」
2. **输入未提交**：输入框下方浮出联想列表（原版是联网 suggest，这里先用本地片单 + 后缀词兜底）
3. **已提交**：分组 chip 行 + 结果行列表
4. **一个都没选源**：「未选择搜索源」提示（原版没有这个态，是我们加的边界）

| 项 | 实测（measure.py 截图坐标） |
| --- | --- |
| 输入框 | x 240–1625（1385 宽）× 高 48，圆角 13，`searchFill` |
| 输入框内 | 左内距 14，搜索图标 15，占位文字 15px；有文字时右侧 18 圆清除钮 #BFBFC2 |
| 严格胶囊 | 42×26，圆角 13；关 `searchFill` + 深字，开 `primaryDim` + 白字 |
| 源选择图标 | 16px，x 1699–1715 |
| 取消 | 15px，`primaryDim`，墨迹 x 1739–1769 |
| 空态 | 图标墨迹 42×43、标题 20px w600（墨迹 y 562–581）、副标题 14px（y 596–608） |
| 联想浮层 | x 240–1903，顶在 header 下 6px；行高 42，图标 13 + 16 间距，文字 13 |
| 分组 chip | 高 34，圆角 17，内距 16，间距 9；选中 `primaryDim` + 白字 |
| 还有 N 个站点 | 星形图标 13 + 文字 13 #6E6E73 |
| 展开圆钮 | 直径 36，#F6F6F8 |
| 结果行 | 整行 1664×108，间距 10，圆角 12；海报 60×90 内距 10；文字列从 +90 起 |
| 结果行三行 | 标题 16 w600（距顶 19）、备注 12.5（47）、站点胶囊 高 22 圆角 6（71） |
| 右下圆钮 | 直径 56，#F6F6F8，距右 24 距底 12 |

**严格** 语义实测：同一关键词 关=75 条（包含匹配）、开=15 条（标题全等）。

「搜索哪些资源」弹窗：558×561，**中心落在内容列 1072 而不是窗口 960**（靠
`insetPadding` 左边保留 sidebar 宽度实现）；标题墨迹距顶 25，源行高 58，
下面那行提示紧跟最后一个源，弹窗剩余高度留空（原版就是这样，不是我们少画了）。

数据来源：`lib/services/search.dart` 的 `searchCatalogue()` 从本地片单出结果，
站点名取自 `_demoSites`（即配置 bundle 里的 59 个真实站点），每个标题按稳定哈希
分摊到约 70% 的站点。Phase 2 只需把 `searchCatalogue` 换成真实站点搜索，UI 与状态机不动。

#### 站点清单是真的，不是编的

猫源这类"js 源"没有 JSON 配置：`index.config.js` 只有主题，站点全在 9MB 的
`index.js` 里，每条 spider 以 `meta:{key:"duoduo",name:"\u300C\u76D8\u300D\u591A\u591A",type:3}`
开头，宿主再加 `nodejs_` 前缀（所以原版 preferences 里是 `homeSite: nodejs_jianpian`）。
`tool/extract_config_sites.py` 把 61 条 `meta` 抽出来，去掉两条非影视站点
（`baseset` =「设」配置面板、`webpage` = type 7 网页入口），正好剩 **59 个** ——
与用户在资源页看到的数字一致。名字自带 `「盘」/「直」/「荐」` 前缀，所以
chip 与结果胶囊**直接显示 name，不再自己拼前缀**（之前写死 `'「盘」 $site'`，
真实名字一来就变成"「盘」 「盘」多多"）。

### Phase 2 — 源接入（灵魂）

#### 已落地：源 → 站点的数据流（纯本地部分）

原版的数据链是 `源(配置地址) --解析--> 站点列表 --fan-out--> 结果`，而重建版原先
只有"源"这一层，站点是搜索页写死的 `demoSites` 常量 —— 源成了孤岛，只有资源页读它。

现在这条链是通的，而且没有一行需要联网：

| 环节 | 位置 | 说明 |
| --- | --- | --- |
| 站点模型 | `models.dart` 的 `SiteInfo` | `key` / `name` / `type` / `api` / `ext` / `enabled`；`key` 对应原版历史里的 `siteKey` |
| 源携带站点 | `SourceInfo.sites` | 序列化时 sites 为空就整个省略，老数据的 JSON 形状不变 |
| 配置解析 | `services/site_parser.dart` | 纯本地 JSON：`{"sites":[…]}`、裸数组、`{"config":{"sites":[…]}}`、每行 JSON、每行 `名称$地址$ext`；带 BOM 容错 |
| 唯一取数口 | `AppStore.sitesForSelection(sel)` | 按选中的源取站点、按显示名去重。搜索 fan-out 与资源页计数都读它 |
| 消费方 | `LcbSearch.sitesProvider` | shell 把 store 的取数函数注入搜索状态，页面不认识"源"这个概念 |

几个必须记住的设计点：

- **`searchable: 0` 的站点保留但 `enabled=false`**，而不是丢弃 —— 用户可以在编辑里打开。
  解析结果同时报 `silenced` / `invalid` 两个计数，避免"文件里明明有 12 个却只出 10 个"。
- **搜索状态通过注入的闭包取站点**，不直接读全局。这样删源、静音站点、粘贴新配置
  都会立刻改变下一次搜索，中间不需要任何 rebuild 额外逻辑。
- **`_siteCarries` 用显示名做 hash**，不用 key。store 已经按显示名去重，显示名就是
  chip 的真实身份；用 key 会让之前从原版量到的分布全部变掉。
- **默认站点种子要迁移**：上一版写进 `flutter.sources` 的源没有 `sites` 字段，
  不补种的话升级后 fan-out 是空的（搜索一片空白）。`_backfillDemoSites` 在 load 时
  补一次并写回，有专门的回归测试。
- **12 个占位站点也要迁移**：更早的构建塞了 12 个手写名字（`wanou`/`naixi`/…），
  库里已有数据的安装不会走"空列表"分支，所以同一函数还会认出这批 key、换成真实
  59 个，并保留用户关掉的开关与他自己加的站点。两个分支都有回归测试。
- **资源页状态行改成"当前使用 · N 个站点"**，不再显示存死的"58 部"。原版能显示部数
  是因为它真的抓过目录，我们没抓，编一个数字只会在验收时变成 bug 报告。等真实抓取
  落地再换回"部"。

**当前入口只有一个**：资源页顶栏 `+` 直接打开「添加影视源」（粘贴配置文本）。
原版的「添加资源」是 3 组 9 项（Emby / 飞牛 Jellyfin / TVBox 影视源 / 直播频道 /
粘贴配置 / 导入文件 / 导入直播列表 / 导入文件夹 / 从 ZIP 导入），其余 8 项分别需要
网络拉取或 spider 运行时，属于下一步。

#### 还没做的（真正的灵魂部分）
- 猫源宿主：Node.js + fastify，需要实现宿主注入的 `catServerFactory`、
  `catDartServerPort`、`messageToDart`，以及 `js2p://_WEB_` 协议
- TVBox：CPython + JS spider，参考原版 `py_host` / `spider_channel`
- 从配置地址联网拉取（现在只能粘贴/导入本地内容）
- 挂载：Emby / WebDAV / AList / 网盘
- 可用性度量：不只判 `supported`，补 `latencyMs` / `movieCount` / `checkedAt`

### Phase 3 — 播放链路
`media_kit` + libmpv。**必须规避原版的三类 bug**，见下节。

### Phase 4 — 外设模块
弹幕（dandanplay）、刮削（TMDB/Bangumi/豆瓣）、下载、字幕、投屏 DLNA、
备份同步（WebDAV）。

### Phase 5 — 多端
TV 端焦点导航（原版 `ui/tv/*` 共 9 个文件）、Android 适配、AI 辅助（集名清洗、
字幕翻译）。

## 五、原版缺陷清单（重建时必须规避）

这三条来自对原版 1.0.0 / 1.0.6 的实测，是它的核心病灶，重写时要在架构层解决，
而不是等复现了再打补丁。

1. **定位基准被污染**：`duration` / `position` 在未就绪时被用于 `seek`，代理位置
   算成 0，于是"按右键跳回片头"。
   → 对策：所有 seek 走一个 `PlaybackClock`，只有 `duration > 0 && position 有效`
   时才允许换算；seek 请求排队，等时长就绪再执行。

2. **广告段污染时间轴**：源站把贴片广告塞进同一条流，广告段的时间轴被写入
   `_lastPosition`，切正片时 `_tryRecover → _resumeAt(脏位置)`，导致从片头起播。
   → 对策：恢复位置只认持久化的 `history.durationMs` 校验过的时间点；
   检测到时长突变（±20% 以上）时丢弃当前位置，改从历史位置恢复。

3. **自动跳片头与续播争抢**：`skipIntroOutro` 的自动 seek 和 resume 定位抢同一次
   跳转。
   → 对策：启动阶段串行化——先 resume，再跳片头，两次 seek 合并为一次最终目标。

## 六、运行时版本（与原版严格对齐）

原版 1.0.6 的技术栈版本是从二进制里读出来的，不是猜的：

| 组件 | 原版版本 | 提取方法 |
| --- | --- | --- |
| Flutter | **3.44.9**（framework `6b182d2`） | Dart 3.12.2 只对应 3.44.2–3.44.9；取该系列末版 |
| Dart | **3.12.2**（stable，2026-06-09，hash `9fc941453ebc5`） | `flutter_windows.dll` 内嵌版本串 |
| Node.js | **18.20.4** | `node/node.exe --version` + PE 版本资源 |
| Python | **3.11.9** | `python/python.exe --version`，`python311.dll` |
| mpv | **v0.41.0-1421-ga687796d9** | `libmpv-2.dll` PE 版本资源 |
| 打包版本 | 1.0.3+4 | `BieCuiLe.exe` 版本资源（包号 1.0.6，作者未同步） |

**Node / Python / mpv 直接复用原版包里的二进制**，天然 100% 一致，不需要重新编译
或找版本：

```
BieCuiLe-1.0.6-windows-x64/node/node.exe          67MB  Node 18.20.4
BieCuiLe-1.0.6-windows-x64/python/                39MB  CPython 3.11.9
BieCuiLe-1.0.6-windows-x64/libmpv-2.dll          101MB  mpv 0.41.0
```

Phase 2 做猫源宿主时把 `node/` 整体内嵌；Phase 3 让 `media_kit` 指向原版
`libmpv-2.dll`，而不是它自带的那份。这样源站兼容性和解码行为都与原版同源。

## 七、开发

```bash
cd LaiCuiBa
flutter run -d windows          # 热重载调试
flutter build windows --debug   # 出包到 build/windows/x64/runner/Debug/
flutter test                    # 冒烟测试
```

环境约束（**已锁定，勿随意升级**）：

- **Flutter 3.44.9 / Dart 3.12.2**，与原版同一 framework revision。锁在 `.fvmrc`、
  `.flutter-version`、`pubspec.yaml` 三处；`dart run tool/verify_toolchain.dart`
  校验当前 SDK，不一致直接非零退出。
- 本机 `E:/app/Android/flutter` 已 checkout 到 `3.44.9`。切回旧版用
  `git -C /e/app/Android/flutter checkout 3.24.5`，但那会让本工程版本校验失败。
- 代码使用新 API（`Color.withValues`），不要写回 `withOpacity`。
- `window_manager ^0.5.2`（3.44 起可用；旧版 0.4.3 是为兼容 3.24 才降级的）。
- 换 SDK 后必须 `flutter clean`，否则增量缓存不会重拷 material 字体，
  `flutter_assets/fonts/` 为空、图标全变方块。
- 截图对照脚本：`../.probe/shot_win.py <窗口标题> <输出.bmp>`，会临时置顶，
  避开被前台窗口遮挡导致的抓屏错误。

## 八、边界

仅自用与自维护，不分发、不内置任何付费内容或破解手段。

**代码层面**：不复用原版代码。原版是闭源商业软件，且其 Dart 部分是 AOT 机器码，
本来也拿不到。

**资源层面**：`assets/` 下除字体外的美术资源（图标包 webp、小组件样图、
加载动画）是从原版包中原样提取的，属于原作者的版权资产。自用无碍；若将来要分发，
这批图必须重画或替换，`lib/core/assets.dart` 里的键名保持不变即可平滑换图。
字体 `LcbSerif` 为 SIL OFL 1.1，可随软件分发。

**脚本层面**：`cat_host.js`、`widgets/*.js`、`php/*.php`、`python/*.py` 是原版
以资源文件形式附带的明文脚本，复制在 `../.probe/bcl106-hosts/`，**仅作协议参考，
不进本仓库**。Phase 2 落地时按协议重写，不搬运原文件。

**⚠️ 已通过资源包修正的一个判断**：`lib/core/theme.dart` 的色值原先全部来自截图
采样，浮点误差明显；后续应以 `liquid_glass_widgets` 的实际渲染参数与 `i18n`
文案为准重新校准，截图只用于校验尺寸与间距。

---

## 附录：原版资源与依赖清单（逆向所得）

### A. 资源包（`data/flutter_assets/`，79 个 assets 文件）

| 路径 | 内容 | 用途 |
| --- | --- | --- |
| `assets/app_icons/` | 39 个 webp + `icons.json` + `standard.png` | 图标包选择器，“派大星图标包”四组：BieCuiLe / 线条 / 画家 / 团子 |
| `assets/i18n/` | `en/es/it/ja/ru.json` + `s2t.txt`(90KB) | 210 条文案，**中文是源语言，键名即中文原文** |
| `assets/widget_samples/` | `p1-p8.jpg` + `b1-b8.jpg` + `samples.json` | 桌面小组件样图，含真实片名/年份/评分/简介 |
| `assets/loading/lunyi.webp` | 244KB | 加载动画 |
| `assets/tv/bg.jpg` | 224KB | 电视模式背景 |
| `assets/shaders/Anime4K_Upscale_CNN_x2_S.glsl` | Anime4K CNN x2 | 超分着色器 |
| `assets/pinyin.txt` | 831KB | 拼音搜索索引 |
| `assets/torrent_trackers.txt` | 2.8KB | BT tracker 列表 |

已搬入 `assets/`，共 71 个文件 6.4MB，键名集中在 `lib/core/assets.dart`，
`test/assets_test.dart` 校验每个文件确实进了包。

### B. 依赖清单（`app.so` 字符串表中的 `package:` URI）

`NOTICES.Z`（解压 1.4MB）只给许可证不给版本号，版本靠着色器文件集合比对确认。

| 包 | 作用 | 备注 |
| --- | --- | --- |
| `liquid_glass_widgets` | **液态玻璃** | 73 处引用 + 5 个 .frag；本地 1.18.0 的着色器集合与原版完全一致 |
| `media_kit` + `media_kit_video` + `fvp` | 播放内核 | `fvp` 是 mpv 后端（非默认 libmdk） |
| `canvas_danmaku` | 弹幕渲染 | |
| `reorderable_grid_view` | 可拖拽网格 | 首页分类排序 |
| `mobile_scanner` + `qr_flutter` + `qr` | 扫码导源 | |
| `flutter_svg` + `cached_network_image` + `octo_image` | 图片 | |
| `dio` + `http` + `http_parser` | 网络 | |
| `petitparser` + `xml` + `html` + `csslib` + `xpath_selector` | 网页解析 | 刮削与源解析 |
| `pointycastle` + `crypto` + `archive` | 加密/压缩 | |
| `provider` + `rxdart` | 状态 | |
| `window_manager` + `screen_retriever` + `wakelock_plus` | 桌面外壳 | |
| `file_picker` + `windows_file_picker` + `package_info_plus` + `shared_preferences` + `path_provider` + `url_launcher` | 系统集成 | |
| `image` | 图像处理 | 取色、封面处理 |
| `vector_graphics(_compiler)` | 矢量图标 | |

### C. 功能面（由 210 条 i18n 键反推，比截图可见范围大一个量级）

外观与外观模式/强调色/字体字号/液态玻璃/自适应颜色、电视模式与遥控器键盘、
播放内核与解码方式切换、跳过片头片尾、上下滑动换集、短剧预载、弹幕源、
外挂字幕/音轨/视轨、倍速、画面比例与对比度饱和度色相伽马、黑边虚化、
投屏、下载管理、网盘账号挂载、磁力播放、推送识别、网络代理与服务代理、
备份与恢复、收藏夹管理、自定义组件与新建页面、追更与追更平台、
多语言、用户协议。

### D. 明文脚本（`../.probe/bcl106-hosts/`，仅参考）

| 文件 | 行数 | 内容 |
| --- | --- | --- |
| `desktop/cat_host.js` | 136 | 猫源宿主：每个源跑在独立 Worker（避免争抢 `globalThis`）、自起 HTTP、端口回传 Flutter、stdin 断开即退出 |
| `desktop/widget_host_node.js` | 150 | 小组件宿主 |
| `desktop/linkedom.js` / `polywasm.js` | 310KB | 源站依赖的 DOM / wasm 垫片 |
| `widgets/douban|bangumi|mikan|tmdb.js` | 1230 | 四个刮削站点脚本全文 |
| `php/lib/spider.php` + `HtmlParser.php` | 20KB | PHP 源支持 |
| `python/runner.py` + `desktop_host.py` | 410 | TVBox CPython spider 宿主 |

### E. 界面实测参数（截图逐像素采样）

系统 DPI 为 96（100% 缩放），所以截图物理像素 = 逻辑像素，无需换算。字号是先量
CJK 墨迹高度、再用本工程同字体的 13px→墨高 12px 做标定反推的。

**截图坐标系有个 8px 坑**：无边框窗口 SetWindowPos 到 (0,0) 后，DWM 保留一圈不可见
边框，`GetWindowRect` 报 (0,0)–(1920,1040)，但真正绘制从屏幕 (8,8) 开始。所以屏幕
坐标减 8 才是 Flutter 逻辑坐标。下面凡标「内容坐标」的都是减过 8 的。

| 项 | 实测值 |
| --- | --- |
| 顶部横带总高 | **60px**，品牌名 / 页面标题 / 窗口按钮**在同一行** |
| 横带下方分隔线 | 1px `#E5E5EA`，**只跨内容列，不跨侧栏** |
| **侧栏宽** | **224**（屏幕 0–231）。之前记成 232 是被上面那 8px 带偏的 |
| 侧栏底色 | `#F5F5F7`；页面底色 `#FFFFFF`（与卡片相反，别搞反） |
| 顶栏左内边距 | 42（页面标题墨迹在内容坐标 274） |
| 顶栏搜索框 | **232×34**，圆角 9，`#EFEFF2`，右侧内嵌 `Ctrl K` |
| 内容左内边距 | **40**（卡片左沿 = 224 + 40 = 264） |
| 设置卡片 | `#F6F6F8`，圆角 14，行内分隔线 1px `#F0F0F3`，缩进 66 |
| 设置行高 | 70；图标圆 36，圆内图标 19；图标↔文字 16 |
| 设置行标题 | 17px / w600；副标题 13.5 / `#8A8A8F`；分组标签 12.5 / `#B0B0B6` |
| 开关 | 50×30，圆角 15，滑块 26；关 `#E2E2E2`，开 `#9186C2`（= `primaryDim`） |
| 设置图标配色 | 系统色：`#5856D6` `#FF9500` `#34C759` `#007AFF` `#FF2D55` `#AF52DE` `#32ADE6` |

### F. 首页：三处尺寸都是自适应的

窗口拉大后并不会等比放大所有东西，原版有三套不同的解析式。三个式子都用
**内容列宽**（窗口宽 − 224），不含左右 padding：

| 元素 | 解析式 | 1920（内容 1680） | 1400（内容 1168） |
| --- | --- | --- | --- |
| hero 高度 | `min(contentW × 0.37, windowH × 0.54)` | 561 | 430 |
| 继续观看卡宽（16:9） | `min(contentW / 3.5, 360)` | 360 | 331 |
| 竖版卡宽（2:3） | `min(contentW / 7.25, 196)` | 196→294 高 | 161→242 高 |

拟合方式：原版分别在 1920×1040 与 1400×900 下量两次，取两条曲线的交点。
hero 单看宽度比例（0.368 / 0.332）或高度比例（0.478 / 0.539）都对不上，必须取两者的
较小值才同时吻合；剩下两个是「一屏几张」的换算，卡片统一 2:3 / 16:9 不变形。

其余实测：

| 项 | 实测值 |
| --- | --- |
| hero | 左右**不内缩**，从 224 铺到右边缘；底部往白渐变起于 0.56，1.0 纯白 |
| hero 标题 | 44px 衬线，墨迹 247–284（内容坐标） |
| hero 海报 | 327×460，距顶 18、距右 76，圆角 14 |
| hero 分页点 | 距底 25，选中 18×6，未选中 6×6 |
| 卡片角标 | 评分 + 类型标签**并排贴在左上角**（不是左右各一个），距边 8 |
| 分区标题 | 20px 衬线，墨迹高 18 |
| 分区结构 | 电影 → 电视剧 → 动漫 → 综艺，每行 8 张横向滚动 |
| 行内间距 | 卡片间距 18；标题→卡片 18；卡片→标题 12；分区之间 38 |

**液态玻璃的真实作用面**：设置项原文是「关闭后底栏与悬浮按钮使用纯色」，即它只
影响**底部栏**和**悬浮按钮**，默认关闭。实测在首页与设置页开关前后逐像素对比，
除了开关本身（bbox 1266,472–1314,500）**没有任何像素变化** —— 首页本来就没有玻璃层。
所以不要在首页/侧栏上叠加玻璃，等实现底栏与悬浮按钮时再接入
`liquid_glass_widgets 1.18.0`。

### G. measure.py 的坐标偏移（务必记住）

`.probe/measure.py` 把窗口摆到 `(-8, -8, w+16, h+16)`。Windows 无边框窗口的
不可见边框是 **左/右/下各 8、上 0**，所以：

- 客户区实际顶部落在**屏幕 y = -8**，横向落在 x = 0。
- 截图裁掉四周 8 后，图上的 y 比 Flutter 逻辑 y **小 8**，x 与逻辑坐标一致。
- `measure.py click` 用的是屏幕坐标，因此 **screen y = 逻辑 y − 8**。

也就是说：截图上量到分隔线在 52，对应逻辑 60（顶栏 60 高）；要点逻辑 y=318 的
侧栏项，就点屏幕 310。表 E/F 与本文件里的实测值都是**截图坐标**，可直接和
`measure.py shot` 的新图对齐。

**点击不可靠时改用 `.probe/click_client.py`**：复刻版从后台 shell 启动时，
`SetForegroundWindow` 会被 Windows 拒绝，`measure.py click` 的真实鼠标事件会被
别的窗口截走（表现为"点了没反应"）。`click_client.py` 先把窗口摆到同一位置，
再把 `WM_LBUTTONDOWN/UP` 直接 PostMessage 给 embedder 的 `FLUTTERVIEW` 子窗口，
不依赖前台，坐标口径与 `measure.py` 完全一致。

同理，**文字输入**不能用 `SendKeys`（CJK 会丢），也别往顶层 HWND 发 `WM_CHAR`；
要么 `SendInput + KEYEVENTF_UNICODE`（需前台），要么向 `FLUTTERVIEW` 子窗口
PostMessage `WM_CHAR(ord(ch))`（不需要前台，`.probe/type.py` 有实现）。

### H. 三个反复踩到的布局坑

- **Row 默认 crossAxisAlignment.center**：内容比视口矮的页面（详情页只有 ~930 高）
  会被居中、整体下移，看起来像"顶部多了 25px"。shell 里内容列的 Row 必须
  `CrossAxisAlignment.stretch`。
- **`Container(alignment: …)` 会吃满父级宽度**：放进 `Wrap` 做 chip 时，每个
  chip 会变成整行宽。chip 一律用 `padding` 撑高度、不要用 `alignment`；
  确实需要居中又要贴合内容时用 `Center(widthFactor: 1, child: …)`（搜索结果的
  站点胶囊就是这么修的，`alignment:` 一行导致整行被染成淡紫）。
- **CJK 的墨迹位置和字号不是 1:1**：`height: 1.0` 配 YaHei 时墨迹基本等于字号，
  但原版很多地方用默认行高，墨迹会低 4–6px（联想词行、卡片三行）。对照时先量
  墨迹框，再决定是加 `Transform.translate` 还是换行高。
