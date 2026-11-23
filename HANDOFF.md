# LaiCuiBa 交接文档

> 用途：新会话快速接续当前进度。新会话开始后，先让 AI 读本文件 + 工程内
> `ARCHITECTURE.md`，再读 `.workbuddy/memory/2026-11-22.md`、`topics/parity.md`
> 和 `topics/rebuild.md`。
>
> **最后更新：2026-11-23（文档追平到代码提交 `378248f`；538 测试绿）。** 2026-11-22 一整天的工作
> 在本文件「二、当前进度总览」的 11-22 段与 `ARCHITECTURE.md` Phase 3/4 节，
> 更细的日志在 `.workbuddy/memory/2026-11-22.md`。

---

## 一、这个项目是什么

**BieCuiLe 1.0.6（Windows）的 Flutter 重建版**，产品名/目录 `LaiCuiBa`，
Dart 包名 `lai_cui_ba`，可执行文件 `LaiCuiBa.exe`。

核心定位（先理解这一点，避免走偏）：
- 不是"抄源码"，是"按界面与行为重新实现"。原版是 Flutter AOT 机器码（`app.so` 17MB），
  **无法反编译**，能拿到的只有 232 个源文件路径、类/方法符号名、字符串常量、资源包。
- 目标是做一个自己长期维护、并且**从设计上规避原版反复出现的播放 bug** 的等价软件。
- 仅自用/自维护，不分发。原版是闭源商业软件。

技术栈严格对齐原版（已锁定，勿升级）：
- Flutter **3.44.9** / Dart **3.12.2**（framework `6b182d2`），本机 SDK 在
  `E:/app/Android/flutter`（已 checkout 到 3.44.9）。
- 原版 Node 18.20.4 / Python 3.11.9 / mpv 0.41.0 的二进制**直接复用原版包里的**（Phase 2/3 落地时内嵌）。

---

## 二、当前进度总览

| 阶段 | 状态 |
| --- | --- |
| Phase 0 — 界面骨架 | ✅ 完成 |
| Phase 1 — 数据层与页面闭环 | ✅ 完成（详情页 + 搜索页都已落地） |
| Phase 2 — 源接入（灵魂） | 🔶 大部分（源→站点→联网拉取→猫源宿主→搜索/详情/播放/首页片单已通；Emby/Jellyfin 与 WebDAV/AList 挂载已通；Python(TVBox) 宿主、客户端与 store 接入全通；缺 js 少量全局与挂载重登） |
| Phase 3 — 播放链路 | 🔶 大部分（播放时钟 + 续播校验 + 片头片尾（全局/按作品）+ 防休眠 + 轨道选择 + 画面比例/调节 + 信息浮层 + 字幕/弹幕；缺内核切换、手势、投屏/全屏等平台项） |
| Phase 4 — 外设模块 | 🔶 已开两个口（弹幕走弹弹play、字幕本地半 + 外挂已通；刮削/下载/投屏/同步未开始） |
| Phase 5 — 多端 | ⬜ 未开始 |

### Phase 0 已完成
无边框窗口 + 自绘标题栏、Material 3 主题、侧栏/顶栏、首页（hero 轮播 + 续播 + 分区）、
资源/收藏/历史/设置四页骨架。`flutter build windows --debug` 出包全绿。

### Phase 1 已完成（数据层已闭环）
- 资源页接真实 `SourceInfo`（type 图标/类型标签/点击切换 source）
- 收藏独立结构 `flutter.favorites` + `flutter.favoriteFolders`（**不是**合并进 history）
- 收藏夹完整 CRUD（新建/重命名/删除）
- 收藏页分类标签（「全部 N」+ 每文件夹 chip），按 `folderId` 真实计数
- 历史页清空确认弹窗 + 单条 hover 删除
- 首页「继续观看」从历史派生（清空历史 → 首页续播同步消失）
- 设置持久化 `AppSettings`（只建模 UI 读写的字段，其余 ~70 键用 `extra` Map 兜底不丢数据）
- 设置 5 个子页骨架 + 有明确原版字段对应的开关接 store
- 修复两个关键 bug：shared_preferences key 双前缀、seed 数据不持久化
- **详情页**：hero（模糊海报 + 204×306 海报 + 标题块 / 属性标签 / 简介 / 6 个操作按钮）
  + 选集（1-20 / 21-40 分页、当前集高亮、16 列网格）+ 演员阵容 + 分类；
  从历史、收藏、首页卡片、hero「详情」进入，顶栏换成「返回 + 片名」；
  「收藏」按钮真实写 `flutter.favorites`
- `HistoryEntry` 补 `sourceUrl` / `sourceType`（原版跨源定位字段）
- **搜索页**：顶栏展开成输入框（+ 严格 / 源选择 / 取消），空态 → 联想 → 结果三态；
  结果按站点分组（`全部 N` + 站点 chip + `还有 N 个站点`）、结果行点进详情；
  「搜索哪些资源」弹窗（多选源、取消选择全部）；`Ctrl+K` 打开、`Esc` 关闭
- **源 → 站点数据流（Phase 2 的纯本地下半部）**：`SiteInfo` 模型 + `SourceInfo.sites`；
  `services/site_parser.dart` 纯本地解析 TVBox/catvod 配置（`{"sites":[…]}`、裸数组、
  每行 JSON、每行 `名称$地址`）；`AppStore.sitesForSelection()` 成为搜索与计数唯一取数口，
  `demoSites` 硬编码常量已删除；资源页 `+` 可粘贴配置真实加源，`⋯` 菜单可设当前 / 编辑 /
  删除，编辑里能逐个静音站点；老 `flutter.sources`（无 sites）在 load 时自动补种
- **站点清单换成真的 59 个**：豆儿猫源没有 JSON 配置，站点全在 `index.js` 的
  `meta:{key,name,type}` 里；`tool/extract_config_sites.py` 抽出 61 条、去掉
  `baseset`/`webpage` 两条非影视站点得 59 条，接进 `_demoSites`。老安装里的
  12 个占位名字会由 `_backfillDemoSites` 就地换掉（保留静音开关与用户自己加的源）
- **站点真的联动了**：`SourceInfo.homeSite`（原版同名字段，值 `nodejs_jianpian`）+
  `MediaItem.siteKey`；顶栏两枚 chip 改读 store（源名 / 首页站点名，后者点开是带
  过滤框的站点选择器），详情页「选集」第一个 chip、历史行副标题（"今天 · 「直」荐片"）
  都显示真实站点；搜索源选择弹窗的副标题带上"N 个站点"；源编辑面板 59 行加了
  搜索过滤（`1/59`）。老数据缺 `homeSite` 时在 load 里补，否则 chip 会掉成「盘」多多
- **72 个测试全绿**（`store_test` 43 + `site_parser_test` 11 + `search_test` 8 +
  `assets_test` 3 + `widget_test` 8）、`flutter analyze` 零问题
- **添加资源九个入口 + 本地导入**：`add_source_menu.dart` 三组九项（Emby / 飞牛 Jellyfin /
  TVBox 影视源 / 直播频道 / 粘贴配置 / 导入文件 / 导入直播列表 / 导入文件夹 / 从 ZIP 导入）；
  `source_import.dart` 处理 JSON/每行 txt（tvbox）、m3u/url txt（live，`channelCount`）、
  py/php/js（file 源）、ZIP 解压到 `imported/<name>`（防 `..` 穿越）。Emby/Jellyfin 表单
  密码不持久化。
- **设置页「数据与存储」**：`_dataRows(store)` 八行（本机数据/备份与恢复/下载管理/下载设置/
  源图标包/清除图片缓存/清理 TMDB 缓存/清空观看历史）；`services/backup.dart` 备份导出/恢复/
  删除（`backups/lcb-<stamp>.json`），清空历史带确认。
- **重新检测联网拉取（C1）**：`services/config_fetcher.dart` `fetchConfig(url)` 拉源地址
  （.js→.json 去 md5 后缀容错）→ 复用 `site_parser` 解析 → 回写 sites/homeSite/latencyMs/
  checkedAt，toast「拉到 N 个站点，用时 X ms」；无地址源诚实提示。真机验证（本地 http.server
  3 个假站点）toast「找到 3 个站点，用时 48 ms」。
- **104 个测试全绿**、`flutter analyze` 零问题
- **114 个测试全绿**（C2 真实数据接入后，含 `spider_session` 5 例 + `spider_client` 5 例）、
  `flutter analyze` 零问题
- **201 个测试全绿**（夹具全关 + 首页并发探测 + WebDAV 挂载之后）、`flutter analyze` 零问题
- **Python（TVBox）源宿主**：`assets/runtime/pyhost/py_host.py`（行-JSON 协议、每请求一线程、
  stdout 只给协议）+ `base/spider.py`（按契约重写）+ `services/py_host.dart`（进程 + id 配对）
  + `services/tvbox_source.dart`（home/category/search/detail/play → 模型）；
  `test/py_host_e2e_test.dart` 真起 `python.exe` 跑夹具源 17 项断言（**当轮还没接进 store**）。
  **240 个测试全绿**。
- **TVBox 接进界面**：`services/script_runtime.dart`（懒启动 + 远端 api 下载缓存）、
  `services/local_proxy.dart`（`/proxy` + `/cache` 只绑回环）、`services/tvbox_catalogue.dart`
  （首页片单）；store 的首页/搜索/详情/播放/检测五条路径都分流到 `TvBoxSource`；`py` 卡片
  走真检测。真机截图确认首页画出夹具源的 hero 与「电影」分区。
  e2e 加到 `script_runtime_e2e_test.dart`（含 store 串联）。**271 个测试全绿**。
- **TVBox 聚合源**：`py_host.py` 加 `sites` op（读顶层 `SITES`，只加载模块不 `init`）与
  `__aggregatePlatform` 转发（`home → site_home`、`category/search/homeVideo → call`+`wrap`、
  `detail/player` 按 `平台@@id` 回聚合器）；`script_runtime.expandSites` 在检测时把文件展开成
  平台站点并写回。夹具 `aggregate.py`（两个平台）覆盖展开、转发、回路由、重复检测不重展开。
  真机截图确认首页画出「甲平台」chip 与 `alpha分区` 片单。**280 个测试全绿**。
- **TVBox `.js` 站点**：新建 `assets/runtime/node/js_site_host.js`（同步 `req` 用常驻
  worker + `Atomics` 桥；`pdfh/pdfa` 用 linkedom 的 DOM；注入 `joinUrl/local/getProxyUrl/
  setCache` 等全局），Dart 侧把协议抽成 `services/source_host.dart`，`py_host` / `js_host`
  只是指名二进制；`services/script_runtime.dart` 按 api 后缀（`.py` / `.js`）分流，
  并刻意把 `…/index.js` 留给猫源。真机：夹具 js 源在真实 exe 上画出「JS 夹具」chip、
  hero「三体·全30集」与「电影」分区（三体 / 狂飙），全部来自 `req` + `pdfh` 解析的
  本地站点。**291 个测试全绿**。
- **跳片头 / 片尾 + 防休眠（Phase 3 收尾）**：`services/skip_rule.dart` 是唯一判据——源站
  不给片头时间点，所以沿用原版做法由用户设秒数，两条护栏（单个不超片长四成、合计不超一半）
  把误设挡在外面；`PlaybackClock` 把片头并进**开播那一次决策**，续播落点落在片头里就只跳一次，
  不会「先落 20 秒再弹到 90 秒」；`takeOutro()` 进片尾区间报一次，播放页把它记成「已看完」
  并让 shell 切下一集。`services/awake.dart` 用 `wakelock_plus` 按持有者计数持有锁
  （切集时新页 hold 早于旧页 release，bool 会把锁关掉）。设置页原来那个死开关现在带
  「片头时长 / 片尾时长」两行真值。**313 个测试全绿**。
- **播放时钟落地（Phase 3 核心）**：`services/playback_clock.dart` 收口所有 seek，进度条在时长未知时
  不可拖动，续播位置带 `totalMs` 由播放器用真实时长复核（跨时间轴拒绝、漂移不落盘）；
  新增 `tool/verify_clock_live.dart` 真起 libmpv 自检 9 项；音量/倍速也随关闭持久化。
  **223 个测试全绿**、`flutter analyze` 零问题
- **画质 / 音轨 / 字幕轨选择 + 记住选择（`d292cb2`）**：`services/track_map.dart` 的 `MappedTracks`
  是「Tracks 事件 → 面板选项 + 原始轨道对象」的唯一映射（面板与 `tool/verify_tracks_live.dart`
  共用，避免「面板写粤语、点下去切英文」）；`ui/widgets/track_panel.dart` 四组「线路/画质/声音/
  字幕」，当前项打勾 + 灰字 detail；`TrackPrefs` 只存三个 id（`AppSettings.trackPrefs`），
  失效 id 恢复时忽略、不硬切。**337 测试绿**。
- **设置页「媒体徽章」真值（`d331403`）**：`services/badge_rule.dart` 从 `vod_name`/`vod_remarks`
  正则识别 4K/HDR10+/杜比视界/DTS/Atmos/IMAX/BluRay 等（中文片名没后缀就不画，不回落 demo）；
  `ui/widgets/media_badges.dart` 叠到海报角落、按组配色；总开关/位置/带文字/四组规格全真值。
  Phase 1 至此无死控件。**353 测试绿**。
- **片头片尾按作品单独记（`cec14e1`）**：全局值只是默认，每部作品可带 `SkipOverride` **逐字段**
  覆盖（`null`=跟随全局、`0`=明确没有片头）；入口在播放页底栏 pill → `ui/widgets/skip_panel.dart`；
  `PlaybackClock.updateSkip` 播放中改规则只在人还在片头里时补一次 seek，**绝不重放续播点**。
  **376 测试绿**。
- **字幕：原版 8 档 + 次字幕 + 外挂（`95e6b37` + `c3696e8`）**：`SubtitlePref` 八档（不自动切换/
  简体优先中文/中英/多语/英/日/韩/关闭），简体优先没有简体时退到任意中文；`SecondarySubtitle`
  用 mpv `secondary-sid` + media_kit 的 `secondary-sub-text` 在画面上方自绘；外挂走
  `services/player/subtitle_file.dart`（srt/ass/vtt、zip 解包、7z/RAR 如实报错），按
  `'<作品id>|ep<集>'` 记忆。字号走 `Video.subtitleViewConfiguration`（Windows 上 libass 关闭，
  mpv 的 `sub-font-size` 无效）。**474 测试绿**。
- **弹幕按原版契约接入（`729bcbd`）**：`services/danmaku/{danmaku_api,danmaku_layout,source_danmaku}.dart`
  —— 弹弹play `/api/v2/match` + `/api/v2/comment/{episodeId}`，签名
  `base64(sha256(appId+timestamp+path+appSecret))`；先按片名+集数搜、搜不到才走文件名 match；
  播放页 `DanmakuLayer` 用 Ticker 从真实进度插值（滚动/顶部/底部轨，轨满丢弃）；设置页弹幕源
  可增删改（内置不可删）。**447 测试绿**。
- **首页四轮对齐（`0110720` → `abf181f`）**：首页只问选中的 `homeSite`（删掉「并发探测 8 站 +
  进程级记住上次好站」，那会让顶栏站名与内容来源不一致）；`/category` 发 `{id,page}`
  （TVBox 的 `{tid,pg}` 会让猫源静默回空列表，这是「分类下没片单」的真因）；`filters` 驱动
  顶栏 ⊞「浏览内容」面板；rail 悬浮翻页箭头（直径 38、距边 32、垂直居中于封面）；分类页
  9 列/175/gap 11（列数必须 `round`，`floor` 会差 1px 掉一整列）；无图卡片改 `#EFEFF2` + 胶片图标。
  **501 测试绿**。
- **接着看三条路径对齐历史那一集（`c84155b`）**：继续观看卡 / 历史圆钮 / hero 播放都回历史那一集
  （`store.startEpisodeFor`，集号跨访问重排时 clamp 到末集）；顺手修「从首页播放 TVBox 源按了
  没反应」（`_detail` 为 null 被误判成已离开，改用 `_navigatedAway`）。**507 测试绿**。
- **播放页画面对齐（`c84d9ad` + `aabedbe` + `378248f`）**：`services/picture.dart` 六档画面比例 +
  亮度/对比度/饱和度/色相/伽马（走 mpv 属性）；`services/player_info.dart` 分辨率/帧率/码率
  常驻浮层 + 迷你进度条；返回按钮回左上角裸箭头、主标题纯片名、副标题
  「第N集 · dw×dh · 画质」、底部居中圆角悬浮控制条。**538 个测试全绿**、`flutter analyze` 零问题

---

## 三、Git 状态（重要）

- 本地 `master` 分支，**全部 commit 均未推送**（`git rev-list --count HEAD` 查实际数量，
  本文件不写死数字，避免每次提交都要改）。
- remote 已配置：`origin = https://github.com/zhujinrun/LaiCuiBa.git`，但**从未 fetch/push**，
  本地 master 还没有 upstream tracking。
- 最近 16 个 commit 是 2026-11-22 的播放页/字幕/弹幕/首页对齐（顶 `378248f`
  「align the player page layout with the original」），工作区干净。

**推送由用户自己执行**（项目硬规则，见 `.workbuddy/memory/MEMORY.md`），AI 不主动 push/tag。
如需推送，命令参考：
```bash
git push -u origin master
```

---

## 四、关键架构事实（新会话必须知道）

### 1. shared_preferences 的前缀机制（踩过的坑）
- `shared_preferences_windows` 会**自动给每个 key 加 `flutter.` 前缀**。
- store 里的 key 常量必须写**裸 key**（`'history'`、`'favorites'`、`'favoriteFolders'`、
  `'sources'`、`'current'`、`'settings'`、`'seeded'`），落盘自动变成 `flutter.xxx` 对齐原版。
- 数据文件位置：`C:\Users\lxy\AppData\Roaming\LaiCuiBa\LaiCuiBa\shared_preferences.json`

### 2. seed 持久化的副作用（踩过的坑）
- 首次启动（`seeded=false`）时 seed demo 数据并写盘，之后启动跳过 seed 直接读盘。
- **副作用**：demo 数据一旦写盘，改代码里的 seed 值（比如海报路径）不会再生效，
  必须删 `shared_preferences.json` 才会重新 seed。
- 验证阶段改 seed 内容时，记得先删数据文件再测。
- Phase 2 接真实源后海报走 `coverUrl` 动态获取，这个「改值需清盘」问题会自然消失。

### 3. 收藏是独立结构（推翻了早期错误判断）
- 原版 `flutter.favorites` 是独立数组，条目字段：`key/sourceId/folderId/title/poster/
  payload{siteKey,vodId}/latest/addedAt`（**无** episode/positionMs/durationMs）。
- `flutter.favoriteFolders` 是文件夹数组 `{id,name}`，收藏条目通过 `folderId` 关联。
- 早期「收藏合并进 history（isFavorite/isFollowing）」的判断是错的（来自 notices 文案误读），已纠正。

### 4. 追剧 tab 结论（查清，未动）
- 原版侧栏「列表」组只有收藏、历史两项，无独立追剧入口。
- 原版「追更」走第三方平台 API（Trakt/Bangumi），数据不落本地，属 Phase 4 联网功能。
- 收藏页 header 的「收藏|追剧」tab 是推测，当前空态占位是正确做法。

### 5. 像素对照的硬规则（来自 MEMORY.md）
- 用户是家里电脑（1600×900）远程连开发机（1920×1080@96DPI），远程贴图窗口宽度/缩放不可靠。
- **所有像素测量必须走 `.probe/measure.py`**，在开发机强制窗口到 1920×1040 再截图。
- 截图坐标系有 8px 坑：窗口 SetWindowPos 到 (0,0) 后 DWM 保留不可见边框，屏幕坐标减 8 才是 Flutter 逻辑坐标。

### 6. 运行时版本对齐
- 详见 `ARCHITECTURE.md` 第六节。Node/Python/mpv 直接复用原版包二进制，天然 100% 一致。

---

## 五、代码结构

```
lib/
  main.dart                 无边框窗口初始化 + 入口
  core/
    theme.dart              颜色/字号/间距 token（LcbColors/LcbMetrics/LcbText）
    assets.dart             资源键名（原版提取的 71 个资产）
    store_scope.dart        InheritedWidget 提供 AppStore
    app_info.dart
    detail_nav.dart         详情页跳转通道（LcbDetailScope + openOf）
    nav.dart                页面跳转（LcbNavScope）
    search_state.dart       搜索模式状态（LcbSearch + LcbSearchScope）
    stable_hash.dart        稳定哈希（站点分摊 / 无图卡片）
  models/models.dart        MediaItem/Episode/ContinueWatching/HomeSection/
                            HistoryEntry/FavoriteEntry/FavoriteFolder/AppSettings
  services/
    store.dart              AppStore（数据读写 + seed + 源/站点取数口 + 各 getter）
    site_parser.dart        TVBox/catvod 配置 -> SiteInfo（纯本地 JSON，不联网）
    catalog_sites.dart      豆儿猫源 59 个站点清单（tool/extract_config_sites.py --write 生成）
    config_fetcher.dart     联网拉源配置 -> FetchResult(ok,sites,latencyMs,error,note)
    source_import.dart      本地导入：JSON/txt/m3u/py/php/js/ZIP -> 源
    backup.dart             备份导出/恢复/删除（backups/lcb-<stamp>.json）
    demo_data.dart          演示片单（夹具开关已全关）
    search.dart             搜索结果模型 + searchCatalogue()（按传入的站点 fan-out）
    # 三个运行时，三条路，互不混用：
    spider_session.dart     猫源：node + cat_host.js + 订阅 bundle
    source_host.dart        脚本源协议层（行-JSON）；py_host / js_host 只指名二进制
    script_runtime.dart     脚本源运行时：按 api 后缀分流、懒启动、远端下载缓存
    tvbox_source.dart       脚本源响应体 -> MediaItem / SpiderList
    tvbox_catalogue.dart    脚本源首页片单
    local_proxy.dart        /proxy 与 /cache，只绑 127.0.0.1
    # 源与可用性
    source_catalogue.dart   猫源首页片单（只问 homeSite）
    source_probe.dart       检测 = 真跑一遍（分类数 / 片数 / 耗时）
    media_mount.dart        挂载抽象（Emby / WebDAV 共用）
    emby_client.dart        Emby / Jellyfin 登录、列表、搜索、剧集、直链
    webdav_client.dart      WebDAV / AList（PROPFIND Depth 1）
    # 播放
    playback_clock.dart     播放页唯一 seek 出口（续播校验 / 片头片尾 / 漂移）
    skip_rule.dart          片头片尾护栏（单不超四成、合计不超一半）
    awake.dart              防休眠（按持有者计数）
    track_map.dart          Tracks 事件 -> 面板选项 + 原始轨道
    track_choice.dart       字幕 8 档偏好 / 次字幕 / 记住的轨道
    picture.dart            画面比例六档 + 画面调节五量
    player_info.dart        分辨率 / 帧率 / 码率格式化
    play_target.dart        播放地址 + headers
    player/subtitle_file.dart 本地外挂字幕（srt/ass/vtt、zip、7z/RAR 提示）
    # 内容增强
    badge_rule.dart         从片名/备注识别规格徽章
    danmaku/
      danmaku_api.dart      弹弹play 契约 + JSON/XML 解析
      danmaku_layout.dart   滚动/顶部/底部轨排版（纯逻辑）
      source_danmaku.dart   按片名+集数搜、失败才 match，按源缓存
  ui/
    shell.dart              侧栏 + 顶栏 + 页面切换（详情/搜索/播放都挂在内容列）
    page_header.dart
    pages/
      home_page.dart        首页（hero/续播/分区/⊞ 浏览内容）
      common_pages.dart     资源/收藏/历史页
      detail_page.dart      详情页（hero + 选集 + 演员 + 分类）
      search_page.dart      搜索页（空态 / 联想 / 分组结果）
      grid_page.dart        分类网格页（9 列 / 分页 / 查看全部）
      player_page.dart      播放页（时钟 / 轨道 / 画面 / 字幕 / 弹幕 / 浮层）
      settings_page.dart    设置 + 子页（2003 行，待按原版声明式索引重构）
    widgets/
      hero_banner.dart
      media_card.dart
      poster_art.dart       PosterArt（有图真实封面，无图中性占位）
      rail.dart             首页横滑 + hover 翻页圆盘
      browse_dialog.dart    顶栏 ⊞「浏览内容」分类/筛选浮层
      manage_folders_sheet.dart
      search_sources_dialog.dart 「搜索哪些资源」源选择弹窗
      source_dialogs.dart   添加 / 编辑 / 删除源 + 重新检测
      add_source_menu.dart  添加资源三组九项菜单
      backup_dialog.dart    备份与恢复弹窗
      site_picker_dialog.dart 首页站点选择器（带过滤框）
      shell_header.dart
      media_badges.dart     海报角落规格徽章
      track_panel.dart      线路/画质/声音/字幕四组面板
      picture_panel.dart    画面比例 + 五滑块
      skip_panel.dart       本剧片头/片尾
      player_info_overlay.dart 常驻信息浮层 + 迷你进度条
      subtitle_style.dart   主/次字幕字号与描边
      danmaku_layer.dart    弹幕渲染层（Ticker 插值）
```

---

## 六、剩余工作清单（按优先级）

### ✅ Phase 1 收尾（已完成）
1. ~~**HistoryEntry 补 `sourceUrl`/`sourceType` 字段**~~ — 已完成，接 `copyWith`/`toJson`/`fromJson`，
   并有序列化单测覆盖。
2. ~~**详情页骨架**（tvbox_detail_page/emby_detail_page）~~ — 已完成并做过像素对照
   （尺寸表见 `ARCHITECTURE.md` Phase 1「详情页」节）。现在按 id 查真实详情；
   `demo_data.dart` 的 `detailDemo` 已随夹具关闭不再使用。
3. ~~**搜索结果页**~~ — 已完成：空态 / 联想 / 分组结果 / 源选择弹窗四块都做了，
   像素对照见 `ARCHITECTURE.md` Phase 1「搜索页」节。
4. ~~**设置页「媒体徽章」子页**~~ — 已完成（`d331403`），识别与渲染都是真规格。
   Phase 1 至此无剩余项。

### 🟡 搜索页遗留（可选，不阻塞）
- 搜索已走真实站点（猫源 / TVBox 脚本源 / Emby / WebDAV），失败站点不出组；
  `严格` 在本地按标题精确过滤（源的搜索是模糊包含）。
- 联想词仍是本地片单 + 后缀词兜底；原版是联网 suggest（`services/search_suggest`），未接。
- 「严格」语义已对齐原版（关=包含匹配 / 开=标题全等），条数随源变化。

### 🟡 详情页遗留（可选，不阻塞）
- 原版「换平台」= 跨源搜索同名片源；源能力已具备（搜索 fan-out），UI 仍未接。
- 「下载」「追更」「评论」按钮等 Phase 4 落地，目前只做视觉。
- 选集分页只做了「1-20 / 21-40」这类按 20 切分，未做原版的更多档位（如 100 集以上）。

### 🔶 Phase 2 — 源接入（灵魂）

**已完成（纯本地部分）**
- `SiteInfo`（`key`/`name`/`type`/`api`/`ext`/`enabled`）+ `SourceInfo.sites`，
  sites 为空时整个字段不序列化，老数据形状不变
- `services/site_parser.dart`：TVBox/catvod 配置的纯本地解析，带 BOM 容错、
  重复 key 去重、`searchable:0` 保留但静音、`silenced`/`invalid` 两个计数
- `AppStore`：`sitesOf` / `activeSites` / `sitesForSelection`（按显示名去重）/
  `toggleSite` / `replaceSites` / `addSource` / `updateSource` / `removeSource`
- 搜索改为接收 `List<SiteInfo>`，`demoSites` 常量删除；`LcbSearch.sitesProvider`
  由 shell 注入，页面不认识"源"
- 首页 `heroItems` / `homeSections`、详情 `detailOf` 都收进 `AppStore`，
  Phase 2 换实现时页面零改动
- 资源页：`+` → 粘贴配置加源；`⋯` → 设为当前 / 重新检测（提示待做）/ 编辑 / 删除；
  编辑里「站点 N 个 · M 个参与搜索」可展开逐个启停
- 老数据迁移：`flutter.sources` 里无 `sites` 的演示源在 load 时补种（有回归测试）

**未完成**
- js 宿主的覆盖率取决于源用了什么：`pdfh/pdfa` 常见语法都实现了，`html2map`、`aes`
  之类额外全局没有，遇到会报具体错误
- 本地 js spider 直接执行（猫源宿主只认订阅目录，不认单个文件；单文件走 js 宿主）
- 挂载令牌失效后的**重新登录入口**（目前提示「删掉这个源重新添加」）

**已完成（Emby / Jellyfin 挂载，2026-11-21）**

`SourceInfo` 早有 `username/password` 却从没登录过，卡片只能写「未连接」。这一轮把挂载做成
真能出片的链路，且仍然**零外部源**可自证（假服务器跑在 localhost）：

- `lib/services/emby_client.dart`：`AuthenticateByName`（`X-Emby-Authorization` 头）换
  `AccessToken` + `UserId`；`Users/{id}/Items` 列表与搜索；`Shows/{id}/Episodes` 取集；
  `Videos/{id}/stream?static=true&MediaSourceId=&api_key=` 直链；`Items/Counts` 取库容量。
  Jellyfin 同协议，一个客户端覆盖两种源。所有失败都转成可读中文 `EmbyException`（401 区分
  「账号密码不对」与「登录已失效」）。
- `SourceInfo` 新增 `token` / `tokenUserId`（为空时**不写进 JSON**，老数据形状不变）。
  **密码不落盘**：添加表单点「添加」时真登录，成功只存令牌；失败则对话框不关、显示原因、
  不保存——不产生「看着配好了却拉不到东西」的假源。
- 搜索：在搜索页表现为**单个站点**（站点名 = 源名），因为一台 Emby 就是一个库。
  严格模式在本地按标题精确过滤（Emby 的 `SearchTerm` 是模糊包含）；没命中时**仍回一个空
  分组**，避免页面回落到 demo 片单冒充用户自己的库。
- 详情/播放：剧集逐集生成 `PlayEpisode`，URL 自带 `api_key`，播放器沿用现有 `playLines`
  路径（无需新协议）；电影给单个「正片」。`MediaItem.sourceName` 让详情页站点标签与播放器
  副标题写源名而不是「全部站点」。
- 首页：当前源是已登录挂载时画服务器片库（hero = 前 5 条，一个「影片库」分区）；空库明确
  说「××的影片库里还没有内容」；非挂载源行为不变。
- 检测：`AppStore.probeSource` 对挂载走 `Items/Counts` + 首屏 24 条，写回四个字段，
  卡片显示 `当前使用 · N 部`。
- 验证：`test/support/fake_emby.dart` 起真 `HttpServer` 当假 Emby，`test/emby_client_test.dart`
  15 例覆盖登录/登录失败/连不上、行映射、剧集与电影详情、直链、检测计数、store 分流与严格模式；
  `widget_test` 新增 3 例（挂载源替换首页 demo 片单、表单未登录不保存、缺账号密码先拦下）。

**已完成（夹具全关，2026-11-21）**

用户要求：「demo 调试阶段不要 demo 了，都分不清是不是真实数据。」于是所有夹具出口统一关掉
（`lcbDemoCatalogue` / `lcbSeedSampleUserData`，都是 `false`）：

- `heroItems` / `homeSections` / `detailOf` / `searchCatalogue` / `suggestionsFor` 全部经开关；
  关闭时返回空，**任何页面都不会再拿夹具顶替真实回答**。
- 首页四态：无源 → 引导去资源页；请求中 → spinner；失败 → 「×× 没有答上来」+ 原因 + 重试；
  成功但空 → 「×× 的首页没有取到片单」。
- 搜索新增 `LcbSearch.canSearch`：没有猫源运行时显示「暂时无法搜索」，而不是假装"没结果"。
- 首次启动只 seed 一个可用源，不再 seed 样本历史/收藏；老安装里海报以 `assets/demo/`
  开头的历史/收藏会被一次性清掉（`purgedFixtureRows` 标记）。
- 测试用三个 seam 保持覆盖：`AppStore.seedSampleUserData`、`store.searchStub`、
  `store.detailStub`。

**已完成（WebDAV / AList 挂载，2026-11-21）**

共享目录没有"库 API"，只有一棵文件树，所以形态是**推断**出来的：目录 = 一部作品（里面的
视频是选集），散落的视频文件 = 正片，文件名里解析年份与集数。仍然**零外部源**可自证
（假 WebDAV 跑在 localhost，真的应答 PROPFIND）。

- `services/media_mount.dart`：`MediaMount` 抽象（library / search / detail / probe /
  streamUrl / playbackHeaders / close）。`EmbyClient` 实现它，store 与页面不再认具体客户端。
- `services/webdav_client.dart`：每层一次 `PROPFIND Depth: 1`（**不遍历整棵树**，AList 根目录
  可能有几千条）；`multistatus` 用正则解析（不引 xml 包，命名空间前缀任意）；选集按自然序
  （第1 / 第2 / 第10）；`@eaDir`/`#recycle`/缩略图目录与字幕、图片、nfo 全部过滤；标题去掉
  `2160p`/`x265`/`WEB-DL` 这类发布标记；403/404/401 与传输异常统一成中文 `MountException`。
- **一个目录里放多部不同电影时不是"第1集/第2集"**：每个文件保留自己的片名进选集；单文件目录
  才叫「正片」。这条是踩过的坑：早期一律按集号排，结果"电影"目录里出现"第2集"。
- 播放：共享目录没有令牌可塞进 URL，所以 `playbackHeaders` 带 Basic auth，`PlayerPage`
  把它并到 UA 之上；目录型条目播之前先取 detail（否则会把目录 URL 丢给播放器）。
- store：`webdav` 进 `isMountSource`，首页 / 搜索 / 详情 / 检测**原路走挂载分支**；读不到时
  画空库而不是把异常抛进页面；检测把数量（或拒绝原因）写回卡片副标题
  （`N 部` / `N 个目录` / `未使用 · 待检测`）。
- 添加资源加「WebDAV / AList 网盘」：**先 PROPFIND 验证再保存**，失败不关表单；
  密码存在源记录里（本地 prefs），因为 WebDAV 没有换取令牌的机制。
- 验证：`test/support/fake_webdav.dart` 起真 `HttpServer` 应答 PROPFIND（含鉴权），
  `test/webdav_client_test.dart` 13 例 + `test/webdav_store_test.dart` 8 例。
  真机（本地假共享）首页画出 电影 / 剧集 / 散装片，无任何夹具参与。

**已完成（猫源首页片单，2026-11-21）**

搜索/详情/播放早已走真实源，只有首页还挂着 demo——最后一块「真实源」与「用户看到的」不一致
的地方，现在接上了，仍然**零外部源**可自证（夹具订阅跑在 localhost）：

- `services/source_catalogue.dart`：`home` 取分类 → 最多 5 个分类各翻第一页 → `HomeSection`；
  分类请求并发（`Future.wait` 保序），串行会把首屏拖成「分区数 × 延迟」。
- 站点轮换：`homeSite` 优先，失败再试后面两个（最多试 3 个）——猫源包里几十个站点，
  被指定的那个死掉是常态。
- hero 跨分区取片：按 vod_id 去重、有海报的优先（hero 是全幅背景）、上限 5 张。
- 首页策略（**2026-11-21 已改**：夹具全关，不再有 demo 兜底）：请求中出占位 spinner；
  成功出片单；源明确回答空 → 「×× 的首页没有取到片单」；没源 → 引导去资源页；
  请求失败 → 「×× 没有答上来 + 原因 + 重试」。见「夹具全关」一节。
- **站点探测是并发的**（关键修复）：实测豆儿源 59 个站点里只有 19 个能出 category，而
  `homeSite` 指的「直」荐片不在其中——原来串行试 3 个必然落空。现在每轮并发：先所有候选答
  `home`，再所有活着的同时答第一个分类，两轮延迟内出结果；候选上限 8；单站点 6s 超时；
  本轮成功的站点在进程内记住（不落盘，隔夜死掉的站不能一直被信任）。
- 判定用严格的 `spiderAddressOf`：答应接管首页是个承诺，配置类 TVBox 地址跑不起来。
- 验证：`test/source_catalogue_test.dart` 11 例（hero 挑片 4、`hasSpiderHome` 4、真起 node
  的夹具订阅 3，含「homeSite 指到死站仍能轮到下一个」）；`widget_test` 新增 1 例锁
  「猫源答不上来时首页仍是 demo 且不显示空态/转圈」。

**已完成（spider 宿主 + 真实搜索/详情，2026-11-20）**
- `assets/runtime/node/cat_host.js`：协议重写版宿主（每源一个 Worker，`catServerFactory`/
  `catDartServerPort` 注入，`/ping /load /unload` 带 x-token）；node.exe 由 `tool/sync_runtime.sh`
  从原版包同步（67MB 不进 git）
- `services/cat_host.dart`（起 node 子进程 + 控制协议）、`spider_client.dart`（`POST
  /spider/<key>/<type>/<action>` → MediaItem）、`cat_bundle.dart`（订阅式下载 bundle 到
  `%APPDATA%/cat/<hash>/`，MD5 校验）、`spider_session.dart`（组合三者，懒加载 + 惰性不抛）
- store：`spider` 字段 + `searchReal`/`detailReal`/`homeCategoriesReal`/`categoryReal`
- UI：搜索异步化、详情打开后异步拉真实记录、海报支持网络 URL
  （当时的「demo 秒出 + 失败回退 demo」已在 2026-11-21 夹具全关时删除，现在是
  加载 / 失败 / 空三态，绝不回退夹具）
- 实测：jianpian `search`/`detail` 返回真实片单；`home` 只有分类名、`category` 空

（原「添加资源其余 8 入口」「从配置地址联网拉取」两项已完成，见上。）

**已完成（宿主独立化 + 可自证，2026-11-21）**

用户明确要求：LaiCuiBa 与 Player/Gateway 那条线**相互独立**，宿主不接那边已验证过的
任何真实 spider 源。所以这一轮把宿主做成「零外部源也能证明自己是对的」：

- **自研夹具源** `test/fixtures/cat_source/`：原创的最小猫源，按 catvod 协议实现
  `init / home / category / detail / search / play`，不基于任何真实商业源。宿主会
  往 bundle 的 `data/` 写源数据，所以测试一律拷到临时目录再加载。
- **`tool/verify_host.js`**（node 侧端到端自检，17 项断言）：`/ping`、错误 token 403、
  `/load` 回传端口、`init/home/search/detail/play`、未知站点 404、**bundle 更新后重载**、
  `/unload` 后端口关闭。跑法：
  `./assets/runtime/node/node.exe tool/verify_host.js`（退出码 0 = 全过）。
- **`test/cat_host_e2e_test.dart`**（Dart 侧真起 node.exe 的集成测试，6 项）：覆盖
  `CatHost` / `SpiderClient` 的 `vod → MediaItem` 映射、选集解析、`nid` 取集、卸载语义；
  缺 `node.exe` 时整组自动 skip。
- **修 `SpiderClient` 健壮性**：源卸载或 Worker 崩溃后，`_call` 原来会直接把
  `SocketException` 抛给 UI（`home`/`detail`/`play`/`category`/`search` 都没兜）。现在
  `_call` 失败返回 `null`，各方法翻译成空结果/`null`——宿主不可达应读作「没数据」。
- **宿主 `/load` 幂等重载**：原来只按 id 复用 Worker，订阅更新后 `require` 缓存会让它
  继续跑旧代码。现在复用条件是「同 id + 同 dir + `index.js` 的 mtime 未变」，否则杀掉
  Worker 重起。自检里有专门的「改片名 → 重载 → 读到新片名」用例。
- **`SpiderSession.ensureLoaded(force: true)`**：给将来的「重新检测」用，先 `unload`
  再重新解析 bundle。默认路径保留「已加载就短路」，搜索不会多付一次 md5 往返。

> **fastify 的定位**：`node.exe` 是原版包里拷来的**裸 node（无 node_modules）**，
> 宿主侧不可能也不该 `require('fastify')`。fastify 是**源（index.js）自带**的依赖，
> 源自己起服务后经宿主注入的 `catServerFactory(handle)` 把 server 交给宿主监听；
> 宿主只负责 `listen` 与端口回传。夹具源用 node 原生 `http` 实现同一协议，正是为了
> 证明「宿主不关心源用什么框架」。

**已完成（可用性度量 / 检测，2026-11-21）**

「配置解析成功」被当成「源可用」是假的：`SourceInfo` 里 `latencyMs/movieCount/showCount/checkedAt`
四个字段一直存在，却从来没人写。这一轮补上生产者：

- `lib/services/source_probe.dart`：`SourceProbe.run()` = 强制重解析 bundle → 起 Worker →
  取首页分类 → 每类翻第一页 → 去重片名计数，**全程计时**。`latencyMs` 含 bundle 与 Worker
  启动，是用户真正等的那段。惰性：死源回 `ProbeReport.failure`，不抛异常。
- `AppStore.applyProbe` 写回四个字段；**失败时清计数、留实测耗时**，不让死源挂着旧「58 部」。
- `重新检测` 分流：`spiderAddressOf(source) != null`（`js`/`tvbox` + `http(s)` 地址）→ 真跑检测；
  其它源仍走拉配置文档。本地 `.js/.py/.php` 文件回「还不能直接执行」，不再让 `CatBundle`
  去 `Uri.parse` 一个 Windows 路径然后报下载失败。
- `spiderAddressOf` 同时收紧了 `_jsSource()`：本地文件不再谎称 `canSearchReal == true`。
- 资源卡片：有真实计数就显示 `当前使用 · N 部`（原版就是这个形状），否则退回「N 个站点 / 未解析」。
- 验证：`test/source_probe_test.dart` 用**本地 HTTP 服务把夹具源当成订阅**（`index.js.md5` +
  `index.js` + `index.config.js`），真起 `node.exe` 跑一遍，断言 2 分类 / 2 部 / 耗时 > 0；
  外加 `spiderAddressOf`、`applyProbe`（含跨重启持久化）纯逻辑用例。

### 🔶 Phase 3 — 播放链路（大部分完成）
- `media_kit` + libmpv（暂用 `media_kit_libs_video` 自带的 DLL，尚未换成原版 `libmpv-2.dll`）。
- **`lib/services/playback_clock.dart` 是播放页唯一允许 seek 的地方**，三条原版事故由此关闭：
  1. 定位基准被污染 → 进度条在 `duration == 0` 时不可拖动，`pendingSeek()` 未就绪不换算；
  2. 广告段污染时间轴 → 历史行连 `durationMs` 一起带出（`ResumePoint`），播放器用**真实时长**
     复核，差超 20% 直接拒绝；播放中时长突变（`drifting`）时关闭不写位置；
  3. 跳片头与续播争抢 → 取走即销毁，一回合一次 seek；用户拖动顶掉未执行的续播。
- `start:` 只当提示：`duration` 一到就复核落点，偏超 8 秒才补发一次（HLS 会把 `start` 丢掉）。
- 片头/片尾：`skip_rule.dart` 两条护栏（单个不超片长四成、合计不超一半）；全局值 + 按作品
  `SkipOverride` 逐字段覆盖；`PlaybackClock` 把片头并进开播那一次决策，`takeOutro()` 每回合报一次。
- 防休眠：`awake.dart` 按持有者计数（切集时新页 hold 早于旧页 release）。
- 轨道：`track_map.dart` 唯一映射，`track_panel.dart` 四组面板，`TrackPrefs` 记住选择。
- 画面：`picture.dart` 六档比例 + 五量调节（mpv 属性）。
- 信息：`player_info.dart` 分辨率/帧率/码率常驻浮层 + 迷你进度条。
- 字幕：8 档偏好、次字幕（`secondary-sid` 自绘）、本地外挂字幕（每集记忆）。
- 弹幕：弹弹play match/comment、纯逻辑排版、Ticker 渲染层。
- 验证：`playback_clock_test` 27 例、`skip_rule_test` 9 例、`track_*`、`subtitle_*`、
  `danmaku_*`、`picture_*`、`player_info*`；真 libmpv 自检脚本
  `verify_clock_live` / `verify_tracks_live` / `verify_subtitle_live` / `verify_picture_live` /
  `verify_player_info_live`（远程桌面无 GPU 时信息浮层脚本降级退出 0）。
- 未做：内核切换（mpv/ijk/exo/mdk + 硬解软解，`services/player/` 缺 12 模块）、上下滑动调
  亮度/音量、长按倍速、投屏/全屏/小窗/锁屏/截图、播放失败自动换线路换源、短剧预载、
  播放列表/选集浮层；字幕网站/字体/样式覆盖/PGS 提示/AI 翻译；弹幕 LogVar/视频自带/
  本地 xml-json/字号速度屏蔽词。

### 🔶 Phase 4 — 外设模块（已开两个口）
- **弹幕**：弹弹play 一系已通（搜索匹配 → 取该集 → 排版 → 渲染 + 设置页弹幕源）。
  缺 LogVar 插件、视频自带弹幕、本地 `.xml/.json`、字号/透明度/速度/屏蔽词。
- **字幕**：本地那一半已通（8 档偏好、次字幕、外挂字幕、每集记忆）。
  缺字幕网站（SubHD / 射手网 assrt / OpenSubtitles）+ 在线搜索面板、字体导入与样式覆盖、AI 翻译。
- 刮削（TMDB/Bangumi/豆瓣）、下载、投屏 DLNA、备份同步（WebDAV）未开始。

### 🟡 Phase 5 — 多端（未开始）
TV 焦点导航（原版 `ui/tv/*` 9 个文件）、Android 适配、AI 辅助（集名清洗/字幕翻译）

---

## 七、开发与验证命令

```bash
cd LaiCuiBa
flutter run -d windows          # 热重载调试
flutter build windows --debug   # 出包到 build/windows/x64/runner/Debug/
flutter test                    # 冒烟测试（当前 538 个全绿）
flutter analyze                 # 静态检查（当前零问题）
dart run tool/verify_toolchain.dart  # 校验 SDK 版本对齐

# 猫源宿主端到端自检（不依赖任何外部真实源，17 项断言）
bash tool/sync_runtime.sh
./assets/runtime/node/node.exe tool/verify_host.js

# 真 libmpv 自检（先 flutter build windows --debug）
dart run tool/verify_clock_live.dart /path/to/clip.mp4
dart run tool/verify_tracks_live.dart
dart run tool/verify_subtitle_live.dart
dart run tool/verify_picture_live.dart
dart run tool/verify_player_info_live.dart
```

`tool/sync_runtime.sh` 同步 node.exe、整份 CPython（39MB，git-ignored）与 `pyhost/`
宿主脚本到 `assets/runtime/` 与 build 产物旁；运行时二进制不进 git。

环境约束：
- Flutter/Dart 版本锁在 `.fvmrc`、`.flutter-version`、`pubspec.yaml` 三处，勿升级。
- 代码用新 API（`Color.withValues`），不要写 `withOpacity`。
- 换 SDK 后必须 `flutter clean`，否则图标全变方块。
- 验证必须用 `build/windows/x64/runner/Debug/` 真实产物，不是 `flutter run`。
- **构建前先关掉跑着的 `LaiCuiBa.exe`**（`taskkill //IM LaiCuiBa.exe //F`），否则
  `MSB3073 / INSTALL.vcxproj 退出码 1`。这是最常见的假失败，别误判成代码问题。

---

## 八、项目硬规则（来自 MEMORY.md，务必遵守）

1. **用户自己推送与发布**：AI 只做到「本地提交完成 + 给推送命令」，不主动 push/tag。
2. **提交信息一律英文**，风格 `type(scope): 概述 - 细节`，正文写清根因与验证结果。
3. **版本号三处同步**：`package.json`、`src/main/core/db/init/tbl_setting.json`、
   `src/renderer/src/pages/setting/base/BaseSetting.vue`（注：这是 FengMi/Player 的规则，
   LaiCuiBa 目前还没到发版阶段，暂无版本号同步需求）。
4. 像素测量一律走 `.probe/shot_win.py` / `.probe/shot_client.py`（`measure.py` 已不在仓库），
   强制窗口 1920×1040 再截图；点击/输入见 `ARCHITECTURE.md` 附录 G。

**已完成（Python / TVBox 接入，2026-11-21）**

- `SourceInfo` 不需要新类型：导入的 `main.py` 早就以 `type: 'py'` 存着，配置里的站点
  也带着 `api`。缺的是「谁来跑它」——`scriptSitesOf()` 把三种形状统一成 `SiteInfo`
  （`py` 源 = 一个站点，key 用源 id），之后所有链路只认站点。
- `PyRuntime.sourceFor(source, site)`：首次用到才起 `python.exe` + 回环代理端口；
  api 是本地路径就直接用，是 http 地址就下载到 `<appdata>/LaiCuiBa/LaiCuiBa/pysrc/<md5>.py`
  （同址只下一次）。
- `LocalProxyServer`：`/proxy` 原样转发给源的 `localProxy(params)`（海报、m3u8 都靠它），
  `/cache` 实现 `get+set+del`；只绑 127.0.0.1，转发响应时剔掉 `content-length` 等框架头。
- 首页：`TvBoxCatalogue` 取分类 → 并发取前 5 个分类第一页 → 空分类丢掉；都没片单时说
  「××的 N 个分类下暂时没有片单」。
- 搜索：按站点并发，各出一组（名 = 站点名），`严格` 在本地按标题精确过滤（源是模糊匹配）；
  失败站点不出组。详情：item 上的 `siteKey` 找回同一个 api。播放：**一定**过
  `playerContent`（`store.resolvesPlayUrl`），URL 与 `header` 一起拿回，交给播放器。
- 检测：`TvBoxSource.probe()` 真跑一次，写回分类数与首页片数；`py` 卡片从
  「待宿主执行」变成实测数字。
- 缺口：本地 js spider 仍未接（会得到真实错误，不是空列表）；聚合源与 `.js` 站点已在
  `70d5e42` / `2fc3418` 补齐。

---

## 九、下一步建议

当前工作区干净、538 测试绿、`flutter analyze` 零问题，可以直接验收或继续开发。

1. **验收（可选）**：`flutter build windows --debug` 后运行
   `build/windows/x64/runner/Debug/LaiCuiBa.exe`（构建前先 `taskkill //IM LaiCuiBa.exe //F`）。
   重点看：首页 hero/分区来自选中站、顶栏 ⊞ 筛选、分类网格 9 列、播放页底栏
   （轨道/片头/画面/弹幕）、字幕 8 档与次字幕、继续观看回到历史那一集。
2. **推送由用户自己执行**（AI 不 push）：`git push -u origin master`。
3. **下一步按 `topics/parity.md` 的顺序**（新功能先查原版三处明文，不要自创）：
   - **设置页重构**：原版 `settings_index` 声明式索引 + 设置搜索 + 按域拆子页。
     现在 `settings_page.dart` 已 2003 行，而字幕网站/弹幕源/内核设置都要新增子页，
     先拆再加班。
   - **字幕网站 + 在线搜索面板**：SubHD / 射手网 assrt / OpenSubtitles，
     播放页可搜索、下载并挂到当前集（`services/subtitle/subtitle_search.dart`、
     `ui/widgets/subtitle_search_panel.dart`、`ui/pages/subtitle_sites_page.dart`）。
   - **播放内核层**：`services/player/` 按原版拆域，先 playback_engine（内核切换）、
     playback_recovery、source_video_cache、video_viewport。
   - 零碎：挂载令牌失效重登、js 宿主缺 `html2map/aes`、本地 js spider 直执行、
     弹幕 LogVar / 视频自带 / 本地文件。

---

## 十、历史背景速查

- 原版缺陷清单、依赖清单（liquid_glass_widgets/media_kit/fvp/canvas_danmaku 等）、
  i18n 功能面（210 键反推）、明文脚本参考（`../.probe/bcl106-hosts/`）→ 见 `ARCHITECTURE.md` 附录。
- 更细的工作日志 → `.workbuddy/memory/2026-11-20.md` 和 `topics/rebuild.md`。
- 完整对话记录 → `C:\Users\lxy\.workbuddy\projects\e-code-AndroidProjects-FengMi\2d03b581-3772-42d5-8007-9c2e060e7cc0.jsonl`
