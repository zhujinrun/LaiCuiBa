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
  core/theme.dart        颜色 / 字号 / 间距 token
  models/models.dart     MediaItem / Episode / ContinueWatching / HomeSection
  services/demo_data.dart 演示片单（截图里的真实内容，便于对照）
  ui/
    shell.dart           侧栏 + 顶栏 + 页面切换
    pages/               各功能页
    widgets/             title_bar / hero_banner / media_card / poster_art
```

`PosterArt` 是占位海报（渐变 + 纹理 + 片名），接口上预留了换成真实封面的位置。

## 四、阶段规划

### Phase 1 — 数据层与页面闭环
本地存储（收藏/历史/设置）、`MediaItem` 从源适配器返回、详情页、搜索结果页、
收藏与历史页接真实数据。这一阶段结束时不联网也能把界面点通。

### Phase 2 — 源接入（灵魂）
- 猫源宿主：Node.js + fastify，需要实现宿主注入的 `catServerFactory`、
  `catDartServerPort`、`messageToDart`，以及 `js2p://_WEB_` 协议
- TVBox：CPython + JS spider，参考原版 `py_host` / `spider_channel`
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
