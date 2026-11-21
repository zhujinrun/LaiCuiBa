# LaiCuiBa 交接文档

> 用途：新会话快速接续当前进度。新会话开始后，先让 AI 读本文件 + 工程内
> `ARCHITECTURE.md`，再读 `.workbuddy/memory/2026-11-20.md` 和 `topics/rebuild.md`。

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
| Phase 2 — 源接入（灵魂） | 🔶 大部分（源→站点→联网拉取→spider 宿主→搜索/详情/播放/首页片单已通；Emby/Jellyfin 与 WebDAV/AList 挂载已通；TVBox python 宿主未做） |
| Phase 3 — 播放链路 | ⬜ 未开始 |
| Phase 4 — 外设模块 | ⬜ 未开始 |
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

---

## 三、Git 状态（重要）

- 本地 `master` 分支，**全部 commit 均未推送**（`git rev-list --count HEAD` 查实际数量，
  本文件不写死数字，避免每次提交都要改）。
- remote 已配置：`origin = https://github.com/zhujinrun/LaiCuiBa.git`，但**从未 fetch/push**，
  本地 master 还没有 upstream tracking。
- 最近 3 个 commit 是本次详情页工作（`45756cb` 模型字段 → `9084e8d` 详情页 → 本 docs 提交），
  工作区干净。

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
    search_state.dart       搜索模式状态（LcbSearch + LcbSearchScope）
  models/models.dart        MediaItem/Episode/ContinueWatching/HomeSection/
                            HistoryEntry/FavoriteEntry/FavoriteFolder/AppSettings
  services/
    store.dart              AppStore（数据读写 + seed + 源/站点取数口 + 各 getter）
    site_parser.dart        TVBox/catvod 配置 -> SiteInfo（纯本地 JSON，不联网）
    catalog_sites.dart      豆儿猫源 59 个站点清单（tool/extract_config_sites.py --write 生成）
    config_fetcher.dart     联网拉源配置 -> FetchResult(ok,sites,latencyMs,error,note)
    source_import.dart      本地导入：JSON/txt/m3u/py/php/js/ZIP -> 源
    backup.dart             备份导出/恢复/删除（backups/lcb-<stamp>.json）
    demo_data.dart          演示片单（截图里的真实内容）+ detailDemo
    search.dart             搜索结果模型 + searchCatalogue()（按传入的站点 fan-out）
  ui/
    shell.dart              侧栏 + 顶栏 + 页面切换（详情页/搜索态都挂在内容列）
    page_header.dart
    pages/
      home_page.dart        首页（hero/续播/分区）
      common_pages.dart     资源/收藏/历史页
      detail_page.dart      详情页（hero + 选集 + 演员 + 分类）
      search_page.dart      搜索页（空态 / 联想 / 分组结果）
      settings_page.dart    设置 + 5 个子页
    widgets/
      hero_banner.dart
      media_card.dart
      poster_art.dart       PosterArt（有 image 显示真实封面，否则渐变占位）
      manage_folders_sheet.dart
      search_sources_dialog.dart 「搜索哪些资源」源选择弹窗
      source_dialogs.dart   添加 / 编辑 / 删除源 + 重新检测（联网拉取）
      add_source_menu.dart  添加资源三组九项菜单
      backup_dialog.dart    备份与恢复弹窗
      site_picker_dialog.dart 首页站点选择器（带过滤框）
      shell_header.dart
```

---

## 六、剩余工作清单（按优先级）

### ✅ Phase 1 收尾（已完成）
1. ~~**HistoryEntry 补 `sourceUrl`/`sourceType` 字段**~~ — 已完成，接 `copyWith`/`toJson`/`fromJson`，
   并有序列化单测覆盖。
2. ~~**详情页骨架**（tvbox_detail_page/emby_detail_page）~~ — 已完成并做过像素对照
   （尺寸表见 `ARCHITECTURE.md` Phase 1「详情页」节）。演示数据在 `demo_data.dart` 的
   `detailDemo`（尚公主）与 `detailFor()`，接真实源后替换为按 id 查详情。
3. ~~**搜索结果页**~~ — 已完成：空态 / 联想 / 分组结果 / 源选择弹窗四块都做了，
   像素对照见 `ARCHITECTURE.md` Phase 1「搜索页」节。
4. **设置页「媒体徽章」子页** — 原版无独立 badge settings 字段，暂占位（**唯一剩下的一项**）。

### 🟡 搜索页遗留（可选，不阻塞）
- 联想词现在是本地片单 + 后缀词的兜底；原版是联网 suggest（如「尚公主 历史背景解读」），
  Phase 2 换成真实接口即可，UI 不动。
- 结果来自 `searchCatalogue()` 的 demo 分发（站点名取自原版实测），真实站点搜索在 Phase 2。
- 「严格」开关语义已对齐原版（关=包含匹配 75 条 / 开=标题全等 15 条），但 demo 目录小，
  数量不会一样。

### 🟡 详情页遗留（可选，不阻塞）
- 原版「换平台」按钮是跨源搜索同名片源，需 Phase 2 的源能力；当前仅占位不可用。
- 「下载」「追更」「评论」按钮同样等 Phase 3/4 落地，目前只做视觉。
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
- TVBox：CPython + JS spider（参考原版 `py_host`/`spider_channel`）——需要原版 `python/` 二进制
- 本地 spider 文件直接执行（需要站点 key/type，纯文件路径给不出来）
- ⚠️ 以上都依赖原版包 `node/`、`python/` 二进制 + 联网，**不适合无人值守推进**

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
- UI：搜索异步化（demo 秒出 + 真实结果替换，失败回退 demo）、详情打开后异步拉真实记录、
  海报支持网络 URL
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

### 🟡 Phase 3 — 播放链路（未开始）
- `media_kit` + 原版 `libmpv-2.dll`
- 必须规避原版三类 bug（详见 ARCHITECTURE.md 第五节）：
  1. 定位基准被污染 → 对策 `PlaybackClock`，只有 `duration>0 && position` 有效才换算
  2. 广告段污染时间轴 → 对策只认 `history.durationMs` 校验过的位置
  3. 跳片头与续播争抢 → 对策启动阶段串行化两次 seek

### 🟡 Phase 4 — 外设模块（未开始）
弹幕（dandanplay）、刮削（TMDB/Bangumi/豆瓣）、下载、字幕、投屏 DLNA、备份同步（WebDAV）

### 🟡 Phase 5 — 多端（未开始）
TV 焦点导航（原版 `ui/tv/*` 9 个文件）、Android 适配、AI 辅助（集名清洗/字幕翻译）

---

## 七、开发与验证命令

```bash
cd LaiCuiBa
flutter run -d windows          # 热重载调试
flutter build windows --debug   # 出包到 build/windows/x64/runner/Debug/
flutter test                    # 冒烟测试（当前 201 个全绿）
flutter analyze                 # 静态检查（当前零问题）
dart run tool/verify_toolchain.dart  # 校验 SDK 版本对齐

# 猫源宿主端到端自检（不依赖任何外部真实源，17 项断言）
bash tool/sync_runtime.sh
./assets/runtime/node/node.exe tool/verify_host.js
```

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
4. 像素测量一律走 `.probe/measure.py`，强制窗口 1920×1040。

---

## 九、下一步建议

1. **让用户验收这一轮**：
   - 先跑 `bash tool/sync_runtime.sh` 同步 node.exe 到 assets 与 build 产物，再
     `flutter build windows --debug` 后运行 exe（构建前先 `taskkill //IM LaiCuiBa.exe //F`）；
   - 启动日志应出现 `LcbSpider: runtime ready (...)`；
   - **首页**：默认源会先转圈（首轮要 load 9MB 的 index.js + 探测站点），几秒后出真实分区；
     若失败会写明原因并给「重试」——这是真实回答，不是 bug；
   - **搜索**：输入关键词回车，结果按站点分组，来自真实源；
   - **网盘**：添加资源 → 「WebDAV / AList 网盘」，填 AList 的 `http://IP:5244/dav`
     与账号，能连上才保存；保存后首页画目录、详情画选集。
2. 验收无误后由**用户自己**推送（AI 不 push）：`git push -u origin master`。
3. 下一步自然顺序：
   - **TVBox/CPython 源宿主**（饭太硬等 json 源），需要原版 `python/` 二进制，属打包工程；
   - **播放链路细节**（Phase 3 剩下的）：跳片头 / 广告段 / 续播争抢的串行化，见
     `ARCHITECTURE.md` 第五节；目前播放器是"直开 + 续播 seek"，三条规避还没落地；
   - 或纯本地收尾：设置页「媒体徽章」子页（**Phase 1 唯一剩下的一项**，现在是死控件）。

---

## 十、历史背景速查

- 原版缺陷清单、依赖清单（liquid_glass_widgets/media_kit/fvp/canvas_danmaku 等）、
  i18n 功能面（210 键反推）、明文脚本参考（`../.probe/bcl106-hosts/`）→ 见 `ARCHITECTURE.md` 附录。
- 更细的工作日志 → `.workbuddy/memory/2026-11-20.md` 和 `topics/rebuild.md`。
- 完整对话记录 → `C:\Users\lxy\.workbuddy\projects\e-code-AndroidProjects-FengMi\2d03b581-3772-42d5-8007-9c2e060e7cc0.jsonl`
