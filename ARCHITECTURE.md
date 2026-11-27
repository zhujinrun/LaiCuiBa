# LaiCuiBa

BieCuiLe 1.0.6 (Windows) 的 Flutter 重建版。目标不是"抄一份源码"，而是做一个自己
能长期维护、并且把原版反复出现的播放 bug 从设计上规避掉的等价软件。

工程标识：目录与产品名 `LaiCuiBa`，Dart 包名 `lai_cui_ba`（Dart 只允许小写下划线，
故 import 路径为 `package:lai_cui_ba/...`），可执行文件 `LaiCuiBa.exe`。
代码内前缀统一为 `Lcb`（`LcbColors`、`LcbText`、`LcbPage`…）。

## 当前状态（2026-11-27）

已完成本轮「按原版逐页实测对齐」：资源页、首页、收藏页、历史页、设置页根列表与所有
一级子页（含滚到底的下半部分）；播放线路按名字记忆，历史封面在详情空图时保留。
工程基线：`flutter analyze` 干净、**637 测试全绿**；未 push、未打 tag。

发布链路已接入 GitHub Actions：推 `vX.Y.Z` tag 自动校验版本与 `CHANGELOG.md`、
构建 Windows x64 / Android APK，并从更新日志小节创建 Release（见 `.github/workflows/release.yml`）。
阶段提交：`13c1385 → e343a1d → b7ab67d → 83e638e → 53a6acb → 2655608 → 147d52b`。

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

## 二、界面骨架（Phase 0，已完成）

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
    demo_data.dart       演示片单 + detailDemo（夹具开关已全关，仅测试 seam 使用）
    search.dart          搜索结果模型 + searchCatalogue()（按站点 fan-out）
    # 三个运行时，三条路，互不混用：
    spider_session.dart  猫源：node + cat_host.js + 订阅 bundle（start(config)）
    source_host.dart     脚本源协议层（行-JSON）；py_host / js_host 只是指名二进制
    script_runtime.dart  脚本源运行时：按 api 后缀分流、懒启动、远端下载缓存
    tvbox_source.dart    脚本源响应体 -> MediaItem / SpiderList（两套生态共用）
    local_proxy.dart     /proxy 与 /cache，只绑 127.0.0.1
    # 播放链路（详见第四节 Phase 3）
    playback_clock.dart  播放页唯一 seek 出口（续播 / 片头片尾 / 漂移）
    skip_rule.dart       片头片尾护栏（单不超四成、合计不超一半）
    picture.dart         画面比例六档 + 调节五量
    track_map.dart       Tracks 事件 -> 面板选项 + 原始轨道
    track_choice.dart    字幕 8 档偏好 / 次字幕 / 记住的轨道
    player_info.dart     分辨率 / 帧率 / 码率格式化
    player/subtitle_file.dart  本地外挂字幕（srt/ass/vtt、zip、7z/RAR 提示）
    # 内容增强
    badge_rule.dart      从片名/备注识别规格徽章
    danmaku/             弹弹play API / 纯逻辑排版 / 源匹配
  ui/
    shell.dart           侧栏 + 顶栏 + 页面切换（含详情页 / 搜索态顶栏）
    pages/detail_page.dart 详情页（hero / 选集 / 演员阵容 / 分类）
    pages/search_page.dart 搜索页（空态 / 联想 / 结果）
    pages/player_page.dart 播放页（时钟 / 轨道 / 画面 / 字幕 / 弹幕 / 浮层）
    pages/grid_page.dart   分类网格页（9 列 / 分页 / 查看全部）
    pages/common_pages.dart 资源 / 收藏 / 历史页
    widgets/search_sources_dialog.dart 「搜索哪些资源」源选择弹窗
    widgets/source_dialogs.dart 添加 / 编辑 / 删除源
    custom/             自定义页面：page_editor / widgets_settings_page / widget_repo_settings
    widgets/             hero_banner / media_card / poster_art / rail / browse_dialog /
                         track_panel / picture_panel / skip_panel /
                         player_info_overlay / subtitle_style / danmaku_layer /
                         manage_folders_sheet / subtitle_sites_settings / detail_action_dialogs
  services/widgets/     组件仓库 / 自定义页面数据源（CapyPlayer / Forward / TMDB）
tool/                   开发者脚本 + ci_release.py（tag / changelog 校验）
.github/workflows/      release.yml：tag 推送自动打包并发布
CHANGELOG.md            发布正文来源（Keep a Changelog 格式）
```

`PosterArt` 有真实图片时优先显示，缺图回落到确定性渐变 + 纹理 + 片名占位。

## 关键实现约定（原 `HANDOFF.md` 中仍有效的部分）

- `shared_preferences_windows` 会给 key 自动加 `flutter.` 前缀；store 里的 key 常量必须写裸 key
  （`history` / `favorites` / `favoriteFolders` / `sources` / `settings`），落盘才与原版一致。
  本机数据文件：`C:/Users/lxy/AppData/Roaming/LaiCuiBa/LaiCuiBa/shared_preferences.json`。
- Android 工程跟随 Flutter 3.44.9 模板：Gradle 9.1.0 / AGP 9.0.1 / Kotlin 2.3.20、Kotlin DSL
  （`*.gradle.kts`）。旧的 Gradle 8.3 + AGP 8.1 Groovy 配置会在 CI 里直接失败，不要回退。
- 夹具开关 `lcbDemoCatalogue` / `lcbSeedSampleUserData` 一律 false；没有真实源就空态或失败态，
  不回落 demo。
- 收藏是独立结构 `flutter.favorites` + `flutter.favoriteFolders`，不合并进 history。
- 历史行右侧圆钮打开详情（不是直接播放）；右键进入批量选择；线路按名字记在
  `AppSettings.playLines`，历史 `flag` 只作回退。
- 用户自己 push / tag；CI 在 tag 推送后自动 Release，AI 不主动 push、不打 tag。

## 四、阶段规划

### Phase 1 — 数据层与页面闭环
本地存储（收藏/历史/设置）、`MediaItem` 从源适配器返回、详情页、搜索结果页、
收藏与历史页接真实数据。这一阶段结束时不联网也能把界面点通。

**已完成**：数据层闭环、设置持久化、收藏夹 CRUD、详情页、搜索结果页、媒体徽章（见下节）。
**未做**：详情页的换平台/下载/追更/评论需要 Phase 4 能力。

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
站点名取自 `catalogSites`（`services/catalog_sites.dart`，配置 bundle 里的 59 个真实
站点），每个标题按稳定哈希分摊到约 70% 的站点。Phase 2 只需把 `searchCatalogue`
换成真实站点搜索，UI 与状态机不动。

#### 站点清单是真的，不是编的

猫源这类"js 源"没有 JSON 配置：`index.config.js` 只有主题，站点全在 9MB 的
`index.js` 里，每条 spider 以 `meta:{key:"duoduo",name:"\u300C\u76D8\u300D\u591A\u591A",type:3}`
开头，宿主再加 `nodejs_` 前缀（所以原版 preferences 里是 `homeSite: nodejs_jianpian`）。
`tool/extract_config_sites.py` 把 61 条 `meta` 抽出来，去掉两条非影视站点
（`baseset` =「设」配置面板、`webpage` = type 7 网页入口），正好剩 **59 个** ——
与用户在资源页看到的数字一致。`--write` 直接重写 `lib/services/catalog_sites.dart`
（清单单独一个文件，刷清单不动 store 的逻辑）。名字自带 `「盘」/「直」/「荐」` 前缀，所以
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
- **站点要有去处，不能只在搜索页出现**：`SourceInfo.homeSite` 存"首页从哪个站点取数"
  （原版同一个字段，值为 `nodejs_jianpian`），顶栏第二枚 chip 显示它的真实名字、
  点开是带搜索框的站点选择器（59 行不靠滚动找）；`MediaItem.siteKey` 让卡片记住出处，
  详情页「选集」第一个 chip、历史行的时间副标题都读它。缺 `homeSite` 的老数据在
  load 时补一次，否则 chip 会掉到"第一个启用站点"（曾显示成「盘」多多）。
- **44px 的列表不要拿去放 59 行**：源编辑面板与站点选择器都加了过滤框 + `1/59` 计数。
  `dart format` 会把 59 条 `SiteInfo` 摊成 300 行，所以清单搬进了 `catalog_sites.dart`。
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

#### 猫源宿主（已完成，2026-11-21）

`assets/runtime/node/cat_host.js` 按原版协议重写，不搬运原文件：

- 每个源一个 `worker_threads` Worker —— 源都会往 `globalThis` 挂东西，放一起会打架。
- 注入 `catServerFactory`（源用自己的框架起服务，宿主只负责 `listen` 与端口回传）和
  `catDartServerPort`（`messageToDart` 回传通道，只放行 `toast` / `openInternalWebview`）。
- 控制端口绑 `127.0.0.1` + `x-token`：`/ping` `/load` `/unload`。
- `/load` 幂等重载：同 id + 同 dir + `index.js` 的 mtime 未变才复用 Worker，否则杀掉重起，
  订阅更新后不会继续跑 `require` 缓存里的旧代码。
- 传 `stdin` 参数时标准输入断开即退出（桌面端子进程跟随应用退出）。

**fastify 不在宿主侧**：`node.exe` 是从原版包拷来的裸 node（无 `node_modules`），
宿主不可能 `require('fastify')`。fastify 是源自己的依赖，源起好服务后经
`catServerFactory` 把 server 交给宿主。宿主不关心源用什么框架。

**独立验证（不依赖任何外部真实源）**：

| 载体 | 内容 |
| --- | --- |
| `test/fixtures/cat_source/` | 原创最小猫源，实现 `init/home/category/detail/search/play` |
| `tool/verify_host.js` | node 侧端到端自检，17 项断言（含 bundle 更新后重载、卸载后端口关闭） |
| `test/cat_host_e2e_test.dart` | Dart 侧真起 `node.exe` 的集成测试，6 项；无运行时二进制时自动 skip |

#### 可用性度量（已完成，2026-11-21）

「配置解析成功」不等于「源今天能用」。`lib/services/source_probe.dart` 把检测改成**真跑一遍**：

- `SourceProbe.run()` 强制重解析 bundle → 起 Worker → 取首页分类 → 按分类翻第一页 →
  统计去重片名数，全程计时。`latencyMs` 是用户真正等的那段（含 bundle 与 Worker 启动），
  不是单次 HTTP 往返。
- 写回 `SourceInfo.latencyMs / movieCount / showCount / checkedAt`（`AppStore.applyProbe`）。
  检测失败时**清掉旧计数、保留实测耗时**——死的源上留着上个月的「58 部」是最坏的谎。
- `重新检测` 按源类型分流：能进宿主的源（`http(s)` 订阅地址）走真跑；配置类源仍走拉文档。
  本地 `.js/.py/.php` 文件明确回「还不能直接执行」，不再假装 `CatBundle` 能读本地路径。
- 资源卡片 `当前使用 · N 部` 只在有真实计数时显示，否则退回「N 个站点 / 未解析」。

#### 挂载：Emby / Jellyfin（已完成，2026-11-21）
- `services/emby_client.dart`：`AuthenticateByName` 换令牌 → `Users/{id}/Items` 列表/搜索 →
  `Shows/{id}/Episodes` 取集 → `Videos/{id}/stream?static=true&api_key=` 直链 →
  `Items/Counts` 取库容量。Jellyfin 同协议，一个客户端覆盖两种源。
- **密码不落盘**：添加表单点「添加」时真登录一次，成功只把 `token` + `tokenUserId` 写进
  `SourceInfo`；登录失败对话框不关、显示原因、**不保存**——避免出现「看着配好了却什么都
  拉不到」的假源。
- 搜索在搜索页表现为**单个站点**（站点名 = 源名）：一台 Emby 就是一个库，不是一堆采集站。
  严格模式在本地过滤（Emby 的 `SearchTerm` 是模糊包含，不接管这一层就等于严格开关失效）。
  库里没有命中时**仍然回一个空分组**，不让页面回落到 demo 片单冒充用户自己的库。
- 详情：剧集拉 `Episodes`，一集一个 `PlayEpisode`（URL 直接带 `api_key`），播放器沿用
  现成的 `item.playLines` 路径，无需新协议；电影给单个「正片」。
- 首页：当前源是已登录挂载时，hero/section 改画服务器片库（空的就说「影片库里还没有内容」）。
- 检测：走 `Items/Counts` + 首屏 24 条，写回 `movieCount/showCount/latencyMs`，卡片显示
  `当前使用 · N 部`；令牌失效给的是可执行的话（重新添加即可重新登录）。

#### 猫源首页片单（2026-11-21）
- `services/source_catalogue.dart`：`home` 取分类 → 每个分类（最多 5 个）翻第一页 →
  变成 `HomeSection`；分类请求**并发**（顺序由 `Future.wait` 保持），串行会把首屏拖成
  `分区数 × 单次延迟`。
- 站点：`0110720` 起**只问用户选中的 `homeSite`**（删掉了「并发探测最多 8 个站 +
  进程级记住上次好站」的临时做法，它会让顶栏站名与内容来源不一致）。
- hero 跨分区取片：去重（按 vod_id）、**有海报的优先**（hero 是全幅背景，留灰块最难看）、
  上限 5 张。
- 首页策略（**2026-11-21 夹具全关后**）：请求中出占位 spinner；成功出片单；源明确回答空 →
  「×× 的首页没有取到片单」；没源 → 引导去资源页；请求失败 → 「×× 没有答上来 + 原因 + 重试」。
  两种失败语义分开：没答上来 ≠ 答了分类但分类下没片单。
- 判定用严格的 `spiderAddressOf`（http + `.md5`/`index.js`）：答应接管首页是个承诺，
  配置类 TVBox 地址跑不起来，答应下来只会得到一屏空白。

#### 脚本源宿主：Python 与 TVBox 的 `.js`（2026-11-21）

TVBox 生态里的「源」其实是两种完全不同的东西，这里两种都跑：

- **Python 源**：一个 `main.py`，`from base.spider import Spider` 再重写五个
  `*Content`，靠 `requests`/`lxml`/`bs4`/`pyquery` 干活。原版为此带了一份 CPython
  3.11.9（`python/`，39MB，都在 `Lib/site-packages`）。
- **TVBox js 站点**：`api` 以 `.js` 结尾的单文件，文件顶层直接写
  `function homeContent(filter){ var html = req(HOST); ... }`。它是**同步**风格，
  依赖宿主注入 `req` / `pdfh` / `pdfa` / `joinUrl` / `local` 这些全局。
  注意它**不是猫源**：猫源是 bundle 目录、导出 `start(config)`、由
  `assets/runtime/node/cat_host.js` 跑；`…/index.js` 属于猫源，其余 `.js` 才是这种站点。

两者共用一层协议，所以 Dart 侧只有一份客户端：

| 部件 | 位置 | 说明 |
| --- | --- | --- |
| 运行时 | `assets/runtime/python/` | 原版包整份拷进来（**git-ignored**），`tool/sync_runtime.sh` 同步到 assets 与 build 产物 |
| 宿主 | `assets/runtime/pyhost/py_host.py` | 一行 JSON 进一行 JSON 出；每请求一线程；stdout 只给协议，源自己的 print 全部改到 stderr |
| 源契约 | `assets/runtime/pyhost/base/spider.py` | 按 `base.spider` 契约**重写**（fetch/post/html/regStr/cleanText/getProxyUrl/getCache…），不是搬运原版 |
| js 宿主 | `assets/runtime/node/js_site_host.js` | 实现 `req`/`pdfh`/`pdfa`/`local`… 并把五个 `*Content` 调出去；链表 `linkedom.js`（MIT）提供真实 DOM |
| 协议层 | `services/source_host.dart` | `Process.start` + 行解码 + id 配对；`call`/`sites`/`proxy`/`release`/`ping`，每次调用有超时 |
| 两个入口 | `services/py_host.dart` / `services/js_host.dart` | 只负责指名二进制与桥脚本；`label` 决定报错里写「Python」还是「js」 |
| 源封装 | `services/tvbox_source.dart` | `home/category/search/detail/playTarget` → 模型；`parse!=0`（要浏览器解析）如实回 null |
| 运行时管理 | `services/script_runtime.dart` | 懒启动两个运行时（各一个子进程）+ 代理监听；`sourceFor(source, site)` 按 api 后缀选宿主、解析 api（本地文件或远端下载缓存），按 `source\|site` 复用实例 |
| 应用侧 HTTP | `services/local_proxy.dart` | `/proxy` 转给源的 `localProxy()`；`/cache` 实现 `getCache/setCache/delCache`；只绑 127.0.0.1 随机端口 |
| 首页片单 | `services/tvbox_catalogue.dart` | `home` 的分类 → 并发取前 5 个分类第一页，空分类丢掉；没有片单时说清是谁没有 |
| 聚合源 | `py_host.py` 的 `sites` op + `script_runtime.expandSites` | 读出顶层 `SITES` 展开成平台站点；调用按 `ext.__aggregatePlatform` 转发给 `site_home` / `call`+`wrap`（仅 Python） |

几个刻意的选择：

- **没有控制端口**。猫源用 HTTP + token，因为 node 侧本来就起了个服务；Python 侧
  协议就是管道，多开一个端口只会多一处要守的边界。
- **`call` 返回字符串**，正是 TVBox 的原始响应体。宿主不解析业务 JSON，Dart 才解析，
  于是「JSON 契约」可以单独测，`SourceHost` 也不必认识 `MediaItem`。
- **vod 行复用 `SpiderClient.vodToItem`**（已转公开）：catvod 的字段名就是从 TVBox
  继承的，两套解析各写一份只会慢慢漂移。
- **`init` 的参数裁剪**：`inspect.signature` 数一下源实际要几个参数，多的截掉 ——
  老源少写一个参数是常态，硬传会 `TypeError`。
- **聚合源（`SITES` 展开 / `wrap`）按原版的契约实现**，不是自创协议：

  | 环节 | 契约 |
  | --- | --- |
  | 声明 | 文件顶层 `SITES`（list of dict / dict / list of str），`sites` op 只加载模块、不 `init` |
  | 选择 | 站点 `ext` 里带 `{"__aggregatePlatform": "<平台>"}`；`script_runtime.expandSites` 把文件展开成每个平台一个 `SiteInfo`，`ext` 合并 `SITES` 项自己的参数 |
  | 转发 | `home → site_home(平台)`；`category/search/homeVideo → call(平台, *Content)` 再 `wrap(平台, list)` |
  | 路由 | `wrap` 把 id 改成 `平台@@id`，`detail`/`player` 走标准入口，聚合器自己按前缀路由 |
  | 兜底 | 声明了 `SITES` 却没带平台 → 明确报「这是聚合源，要先选平台」，不是回一屏空白 |
  | 安全 | 站点 `ext` 非空且不是 JSON 对象时不展开（不能既保留原参数又注入选择器） |

  展开发生在「检测」时（唯一需要真跑一次的地方），结果写回 `sites`，第二次检测看到的
  已是带 `__aggregatePlatform` 的站点，不会重复展开。

- **`.js` 的判断比后缀多一步**：`…/index.js` 是猫源 bundle 的入口，其余 `.js` 才是
  单文件站点。两者后缀相同、语义相反，判错一边就是「源没有实现 homeContent」这种
  莫名其妙的失败。判定写在 `script_runtime.dart` 的 `isJsApi()` 里，有单测钉住。

js 宿主有两处绕不过去的工程问题，都不是「加个分支」能解决的：

1. **源是同步写法，Node 没有同步 HTTP**。TVBox 的 js 源整篇都是
   `var html = req(url).content`，`req` 返回 Promise 会全线崩。做法是一个常驻
   `worker_threads` 干活、主线程 `Atomics.wait` 等结果：请求与响应都放在一块
   `SharedArrayBuffer` 里（`flag` 头部 + 请求区 + 响应区），带 generation 号，
   迟到的应答不会被下一个请求认领；worker 回到等待前先 `setImmediate`，事件循环
   才能跑 HTTP 回调。实测一次往返约 60ms（含冷启动）。
2. **`pdfh` / `pdfa` 要有真 DOM**。它们吃的是 `选择器&&属性` 的链式规则
   （`div.item&&a&&href`、`body&&Text`、`:eq(n)`、相对地址补全），没有 DOM 就是
   空手。因此把原版包里的 `linkedom.js`（MIT，单文件 CJS）同步进来，`pdfh/pdfa/pd`
   在这个 DOM 上实现；`Text/Html/Tag/!Text` 与任意属性名都认，`href/src` 会按 base 补全。

注入的全局：`req`（method/headers/body/timeout/buffer + 跟随重定向 + gzip/br）、
`joinUrl`、`base64Encode/Decode`、`md5`、`local`（落脚在 `<appdata>/…/jssrc/js-local.json`）、
`getProxyUrl()`（拼应用自己的 `/proxy?siteKey=…`）、`setCache/getCache/delCache`、
`print` 与 `console.*`（全部改到 stderr —— 源里一句 `console.log` 把协议冲掉是这类
宿主最典型的翻车方式）。

**不做的**（如实报错，不装作支持）：js 源的 `SITES` 聚合不展开（TVBox 的 js 生态对
`SITES` 语义并不统一，展开后无法保证路由回得来），依赖额外运行时的语法（例如
`html2map`）会得到「源没有实现 xxx」或具体的 JS 异常。

**独立验证**分四层，两个运行时都真起（`python.exe` / `node.exe`），夹具是原创的
`test/fixtures/py_source/main.py`（两个线路、`parse=1`、空结果、故意抛异常）、
`aggregate.py`（`SITES` + 两个平台 + `wrap` 前缀）与
`test/fixtures/js_source/main.js`（真 `req` + `pdfh` 拉一个测试里现起的站点）：

- `test/py_host_e2e_test.dart`（23 项）：行-JSON 协议、参数裁剪、port 握手、
  base64 代理回传、异常透传、`release` 后重新 init、`TvBoxSource` 的四条映射，
  以及聚合源的 `sites` / `site_home` / `call`+`wrap` / `平台@@id` 回路由；
- `test/js_host_e2e_test.dart`（7 项）：真 node 跑 `.js` 夹具，验证同步 `req` 与
  `pdfh`/`pdfa` 把真实 HTML 解析成 home/category/search/detail/player、异常原样回传、
  未实现的方法如实报错、`localProxy` 字节回传、`release` 后重新 init；
- `test/script_runtime_e2e_test.dart`（10 项）：本地源启动、`/proxy` 真的打到源的
  `localProxy`、远端 api 只下载一次（且按后缀存成 `.py`/`.js`）、`expandSites` 展开与去重、
  **store 的四条链路串联**（首页 → 搜索 → 详情 → 播放）、「检测展开聚合源后四条链路
  落在选中的平台上」、「`.js` 站点走 node 而不是 Python」、「没有 node 时如实说缺什么」；
- `test/local_proxy_test.dart`（6 项）+ `test/py_store_test.dart`（20 项）：不依赖运行时，
  覆盖 HTTP 端点契约、store 的分流/严格过滤/检测写回，以及 `.js` 与 `…/index.js` 的判别。

**已经接进 store**（`855620f` + 本次）：

- 站点形状只有一种：`scriptSitesOf()` 把「导入的 `main.py` / `main.js`」展开成
  `SiteInfo(key: 源 id)`（一个文件就是一个站点），把「配置里的站点」筛出 `api` 以
  `.py` / `.js` 结尾的那些（`…/index.js` 除外，那是猫源入口）。之后
  跳转、详情、播放都按站点走，不再区分源是哪种类型。
- 首页 / 搜索 / 详情 / 播放四条链路都分流到 `TvBoxSource`：首页走 `TvBoxCatalogue`，
  搜索按站点并发各自出一组（失败的站点不出组，和猫源一致），详情用 item 上的
  `siteKey` 回到同一个 api，播放**一定**过 `playerContent`（`resolvesPlayUrl`）——
  因为 `vod_play_url` 只是它的入参，真实地址和 Referer 只有它知道。
- 资源页「检测」对这类源是**真跑一次**（`TvBoxSource.probe`），把分类数与首页片数写回卡片；
  `py` 卡片的状态行因此从「待宿主执行」变成实测数字。
- 远端 `api`（配置里常见）由 `ScriptRuntime` 下载到
  `<appdata>/LaiCuiBa/LaiCuiBa/pysrc/<md5>.<后缀>`，同一个地址只用下一次；换地址就是换
  hash，自然重下。后缀必须保留：两个运行时靠它选子进程，`.js` 存成 `.py` 就会被送去
  解释器。
- `tvbox` 配置源本身仍靠「检测」联网拉站点：拉回来之后如果站点是 `.py`，下一次检测/打开
  首页就会真的跑起来。
- **聚合源**：`scriptSitesOf()` 对已展开的 `py` 源直接读 `sites`；检测先 `expandSites` 再跑
  probe，展开结果（每个平台一个 `SiteInfo`，`api` 都指向同一个文件、`ext` 带平台选择器）
  写回源并持久化。首页/搜索/详情/播放因此看不出它和普通多站点配置的区别。
  真机自证：夹具聚合源在真实 exe 上画出「甲平台」chip 与 `alpha分区` 片单。

#### 还没做的
- js 宿主的覆盖率仍取决于源用了什么：`pdfh/pdfa` 的常见语法都实现了，但 `html2map`、
  `aes` 之类额外全局没有，遇到会报具体错误而不是装作成功
- 猫源宿主仍只认订阅目录，不能直接跑一个随源下发的 `.js` 单文件（那是 js 宿主的活）
- 挂载令牌失效后的**重新登录入口**（目前提示「删掉这个源重新添加」）


> `js2p://_WEB_` 已核对过：它不是应用侧缺口。该 scheme 由**源自带的 ext 服务**在自己的
> 进程里重写成 `http://127.0.0.1:<源端口>`，宿主与播放器都不需要认识它。

### Phase 3 — 播放链路
`media_kit` + libmpv。**必须规避原版的三类 bug**，见下节。

#### 已落地：`PlaybackClock`（2026-11-21）

`lib/services/playback_clock.dart` 把「播放器说它在 X、总长 Y」翻译成「seek 到 Z，或者什么都别做」。
播放页每一次 seek 的唯一出口，所以三次原版事故从结构上不会再发生：

| 原版事故 | 现在的做法 |
| --- | --- |
| 未就绪就换算 → 跳回片头 | 进度条在 `duration == 0` 时**不可拖动**（`Slider.onChanged: null`）；所有 seek 先问 `pendingSeek()`，未就绪一律不换算 |
| 广告段的时间轴被当成正片 | 每行历史连 `durationMs` 一起带出（`ResumePoint`），播放器用**真实时长**复核：`resolveResume()` 在「记录时的总长」与「这次真正的总长」相差超 20% 时直接拒绝；播放中时长突变（±20%）标记 `drifting`，关闭时**不写**这条位置 |
| 跳片头与续播抢同一次跳转 | `pendingSeek()` 取走即销毁，一回合只发一次 seek；用户拖动会顶掉未执行的续播（`requestSeek` 优先）。片头跳过**并入同一次决策**：先算续播落点，再判断它是否落在片头里，两次意图产出一个目标（见下节） |

`start:` 只当**提示**用：mpv 在加载途中应用它，部分 HLS 流会把它丢掉。`duration` 一到就开始
复核落点：落点与目标相差超过 8 秒才补发一次（同一个目标重复 seek 是无害的，但会造成一次肉眼可见的抖动，
所以只有确实没落地才发）。落点核对没通过（例如贴片把基准带跑偏）时退回片头，而不是把人丢在广告里。

#### 片头 / 片尾：只有用户设过才跳

源站不给片头时间点（猫源的 detail、TVBox 的 `playerContent` 都只有 URL 和 header），
所以任何「自动识别片头」都只能是猜，猜错就把正片跳了。这里沿用原版的做法：
**用户在设置里填片头/片尾秒数，全站通用**；`SkipRule`（`lib/services/skip_rule.dart`）
是唯一判据，两条护栏都在它里面——

- 单个区间不得超过片长的 40%，两个加起来不得超过一半，否则当误设，**什么都不跳**；
- 一秒以下按误触处理；直播（时长为零）永不生效。

越界的理由很实际：90 秒片头对 45 分钟的剧没问题，套在 3 分钟短剧上就会吃掉一半。

`PlaybackClock` 把片头并进**开播那一次决策**：先取续播落点（或 0），再判断它是否在片头里，
是就把目标抬到片头末尾——所以从 0 起播、续播落在第 20 秒、续播点不可信这三种情况
都只产生**一次** seek，不会出现「先落 20 秒再弹到 90 秒」的两次可见跳。用户一旦自己拖过
进度条（`requestSeek`），自动跳过就永久让位，拖回片头看片头不会被弹走。

片尾是另一个方向：`takeOutro()` 在位置进入 `duration - outro` 时**报一次**（同一个时间轴只报一次，
漂移后重新可报）。播放页据此暂停并把这一集记成「已看完」（写 `duration` 而不是当前位置），
shell 决定切下一集还是退出——最后一条不会在演职员表前留下一个「续播 92%」的坑。
两种情况都会在画面上留一行 3 秒的提示（「已跳过片头 90 秒」/「已跳过片尾」），
免得观众以为播放器自己乱跳。

**独立验证（不需要任何外部源）**：

| 载体 | 内容 |
| --- | --- |
| `test/playback_clock_test.dart` | 27 例：未就绪不换算、落点复核、跨时间轴拒绝、拖动顶掉续播、漂移标记、`resolveResume` 边界，以及片头/片尾那 8 组 |
| `test/skip_rule_test.dart` | 9 例：合理值生效、只设一个、直播不生效、超四成拒绝、合计超一半拒绝、短剧套长片头被拦、亚秒误触、负数 |
| `test/store_test.dart` | 续播点带着 `totalMs` 一起返回；贴着贴片录下的一行在 45 分钟真片上被拒 |
| `tool/verify_clock_live.dart` | **真起 libmpv** 跑同一条决策链：6 组场景 15 项断言（无续播不 seek、续播恰好一次且落到 59.96s、`start` 生效时不补发、贴片位置被拒、片头一次跳到 26.96s、片尾在 2:33 报一次且不重复） |

播放器退出时把音量与倍速写进 `flutter.settings` 的 `playerVolume` / `playerRate`
（`AppStore.savePlaybackPrefs`），下一集用同一档继续——和续播位置一起在关闭那一刻落盘，
不做滑块级联写入。

播放期间阻止系统休眠：`lib/services/awake.dart` 包一层 `wakelock_plus`（Windows 上就是
`SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED)`）。它**按持有者计数**，
因为切集时新播放页的 `initState` 早于旧页面的 `dispose`，一个 bool 会走成
`enable → disable` 并把刚点亮的锁关掉；shell 持有一个实例传给它创建的每个播放页。

#### 画质 / 音轨 / 字幕轨（2026-11-21，`d292cb2`）

- `services/track_map.dart` 的 `MappedTracks` 是「一次 `Tracks` 事件 → 面板选项 + 原始轨道对象」
  的**唯一映射**。`TrackOption.id` 同时是显示键和切换键，播放页与
  `tool/verify_tracks_live.dart` 共用这一份——否则会出现「面板写粤语、点下去切英文」。
- `ui/widgets/track_panel.dart` 四组「线路 / 画质 / 声音 / 字幕」；「线路」是 `lineIndex`
  （`playLines`），其余三组是 mpv 轨道。mpv 的 `auto` / `no` 控制词在映射层丢掉，
  `no` 单独映射回 `SubtitleTrack.no()`。
- 记住选择：`TrackPrefs` 只存三个 id（`AppSettings.trackPrefs`）。开播后按
  「id 还存在才应用」，失效 id 直接忽略，不硬切。

#### 画面比例与画面调节（2026-11-22，`c84d9ad`）

原版能力面（app.so 明文）：`画面比例` 六档（保持原始比例完整显示 / 拉伸到屏幕边缘不保留比例 /
保持原始比例铺满边缘可能裁掉 / 宽度铺满高度等比放大超出裁掉 / 高度铺满宽度等比放大超出裁掉 /
裁剪铺满）；`画面调节` 亮度/对比度/饱和度/色相/伽马，文案「0% 是原始画面；这里的亮度和
屏幕亮度分开」。

- `services/picture.dart`：`AspectMode`（短码 → `BoxFit`，`parse` 认不出退回 fit）与
  `PictureAdjust`（五量 -100..100，`mpvProperties` 映射到 mpv 属性名）。
- 播放页底栏「画面」pill → `ui/widgets/picture_panel.dart`（六档 + 五滑块 + 非中性时
  「恢复原始画面」）。三个面板（轨道 / 片头 / 画面）共用右下角槽位、互斥。
- `Video(fit:)` 按档映射；调节走 `NativePlayer.command('set <prop> <value>')`。
  `tool/verify_picture_live.dart` 真起 libmpv，`set` 后 `getProperty` 回读一致
  （mpv 返回 `20.000000` 浮点串，要比 `double.tryParse`）。

#### 信息浮层与迷你进度条（2026-11-22，`aabedbe`）

原版文案：「选中的信息常驻在画面角落，不随操作菜单隐藏。帧率需要 MPV 或 MDK 内核，
ExoPlayer 下显示 --」；迷你进度条「画面最底下一条线：蓝色已播放、浅蓝已缓冲」。

- `services/player_info.dart`：`PlayerInfoField`（分辨率 / 帧率 / 码率）+ 三个格式化函数
  （`dw×dh`、`23.976 fps`、`2543 kbps`，空/零 → `--`）。
- 分辨率来自 `videoParams`（首次解码出帧才有）；帧率/码率在参数到达后走
  `NativePlayer.getProperty`（`estimated-vf-fps` / `video-bitrate`）异步读一次。
- `ui/widgets/player_info_overlay.dart` 的 `PlayerInfoOverlay` / `MiniProgressBar` 独立可测；
  设置里是 `playerInfoFields`（逗号分隔短码）+ `miniProgress`。
- 远程桌面无 GPU 时 libmpv 不解码视频轨，三个属性读不到是环境限制；
  `tool/verify_player_info_live.dart` 据此降级退出 0 并注明。

#### 字幕：8 档偏好 / 次字幕 / 外挂（2026-11-22，`95e6b37` + `c3696e8`）

- **默认字幕 8 档**（`SubtitlePref`，`services/track_choice.dart`）：`auto` 不自动切换、
  `zh` 任意中文（简体优先，无简体回退其它中文）、`zh-en` 中英、`multi` 多语、`en` / `ja` / `ko`、
  `off` 关闭。`label` 逐字用 app.so 原文；语言码认出来但不对时**不再拿标题硬猜**，
  避免「中文标题 + eng 码」错配。
- **次字幕**（`SecondarySubtitle{off,zh,en,ja,ko}`）：mpv `secondary-sid` 选第二条轨
  （media_kit 没 API，走 `NativePlayer.command`），文字取 media_kit 已暴露的
  `stream.subtitle[1]`（即 `secondary-sub-text`），用 `LcbSubtitleStyle.secondaryOf`
  在画面上方自绘（0.8 倍字号 + 描边）。主字幕换了会重挑，绝不和主字幕同轨。
- **外挂字幕**（`services/player/subtitle_file.dart`，原版同名模块）：srt/ass/ssa/vtt/sub
  直接交 mpv（`SubtitleTrack.uri`）；压缩包按魔数认，zip 解到
  `<appData>/subtitles/<包名>/`（条目只留 basename，防路径穿越），7z/RAR 如实报
  「这台设备上解不开」；按 `'<作品id>|ep<集>'` 记忆，文件被删就当作没记过并清记忆。
- **字号不是 mpv 属性**：Windows 上 `PlayerConfiguration.libass` 默认 false，media_kit 把字幕
  当 Flutter 文本画（`sub-text`），所以字号走 `Video.subtitleViewConfiguration`
  （`ui/widgets/subtitle_style.dart` 的 `LcbSubtitleStyle.of(px)`）。别去设 `sub-font-size`，
  那条路在本配置下没有效果。

#### 弹幕：弹弹play 一系（2026-11-22，`729bcbd`）

- `services/danmaku/danmaku_api.dart`：`https://api.dandanplay.net` + `/api/v2/match`
  （`fileName` / `withRelated`）+ `/api/v2/comment/{episodeId}`；签名
  `base64(sha256(appId + timestamp + path + appSecret))`（path 不含查询串），头
  `X-AppId` / `X-Signature` / `X-Timestamp`。`parseDanmaku` 同时吃 JSON 与 XML；
  `401` 明确说「要 AppId/AppSecret」，非弹幕格式给带预览的报错。
- `danmaku_layout.dart`：纯逻辑排版——滚动轨按「尾巴进画」释放、固定轨 4s、
  轨满就丢这条、`blockTop` / `blockBottom` 直接不排。
- `source_danmaku.dart`：先按片名 + 集数搜，搜不到才用拼出来的文件名走 `/match`；
  一个源通了就停；按 `片名|集数|源` 缓存；失败带一句人话。
- 播放页 `DanmakuLayer` 自己用 Ticker 从真实进度插值（进度流 200ms 一次，不插值会一卡一卡），
  排版只在尺寸/表长变化时重算，每帧只 `activeAt` + 画字（描边 2.4 + 填充）；换集清空并重取。
- 设置页：显示弹幕 / 屏蔽顶部 / 屏蔽底部三个真开关 + 弹幕源列表（内置可改凭据、不可删）
  + 添加 / 编辑 / 删除弹窗。

#### 还没做的
- ijk / exo / mdk 安卓内核的**真实实现**（Windows 构建只有 mpv；设置项与切换面板已落地）。
- 上下滑动调亮度/音量的真实手势；长按倍速的设置项已落地但手势未接。
- 投屏 / 全屏 / 小窗 / 锁屏 / 截图的平台实现已落地入口，部分行为仍待真机验收。
- 字幕网站、AI 翻译、弹幕源的入口与设置已落地；字体导入与 PGS/VobSub 提示仍缺。
- 弹幕 LogVar 插件、视频自带弹幕、本地 `.xml/.json` 仍缺。
- 片头/片尾是全局一组 + 按作品覆盖，还没有按单集记（原版也是全局）。

### Phase 4 — 外设模块（部分）

| 模块 | 状态 |
| --- | --- |
| 弹幕 | 🔶 弹弹play 一系 + 设置页源管理已通；缺 LogVar、视频自带、本地 `.xml/.json`、字号/透明度/速度/屏蔽词 |
| 字幕 | 🔶 8 档偏好 / 次字幕 / 外挂 / 每集记忆 / 字幕网站 / AI 翻译入口已落地；缺字体导入、PGS/VobSub 提示 |
| 刮削 | 🔶 TMDB 真片单已通；TMDB API 代理、Bangumi / 豆瓣仍未接 |
| 下载 | ⬜ 下载管理 / 下载设置 |
| 投屏 | 🔶 入口已落地；DLNA 行为待真机验收 |
| 备份同步 | 🔶 本地 JSON 导入导出已通；WebDAV 同步未做 |

### Phase 5 — 多端
TV 端焦点导航（原版 `ui/tv/*` 共 9 个文件）、Android 适配、AI 辅助（集名清洗、
字幕翻译）。

## 五、原版缺陷清单（重建时必须规避）

这三条来自对原版 1.0.0 / 1.0.6 的实测，是它的核心病灶，重写时要在架构层解决，
而不是等复现了再打补丁。

1. **定位基准被污染**：`duration` / `position` 在未就绪时被用于 `seek`，代理位置
   算成 0，于是"按右键跳回片头"。
   → 对策：所有 seek 走一个 `PlaybackClock`，只有 `duration > 0 && position 有效`
   时才允许换算；seek 请求排队，等时长就绪再执行。**已实现**（Phase 3）。

2. **广告段污染时间轴**：源站把贴片广告塞进同一条流，广告段的时间轴被写入
   `_lastPosition`，切正片时 `_tryRecover → _resumeAt(脏位置)`，导致从片头起播。
   → 对策：恢复位置只认持久化的 `history.durationMs` 校验过的时间点；
   检测到时长突变（±20% 以上）时丢弃当前位置，改从历史位置恢复。**已实现**（Phase 3）。

3. **自动跳片头与续播争抢**：`skipIntroOutro` 的自动 seek 和 resume 定位抢同一次
   跳转。
   → 对策：启动阶段合并——续播落点与片头区间算出**一个**目标再发一次 seek。
   **已实现**（Phase 3 片头/片尾）。

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
flutter test                    # 当前 637 个全绿
./assets/runtime/node/node.exe tool/verify_host.js  # 猫源宿主端到端自检

# 真 libmpv 自检（取 build 产物里的 DLL；先 flutter build windows --debug）
dart run tool/verify_clock_live.dart /path/to/clip.mp4
dart run tool/verify_tracks_live.dart      # 轨道映射 / 切换 / 恢复
dart run tool/verify_subtitle_live.dart    # 主/次字幕 + 外挂
dart run tool/verify_picture_live.dart     # 五量 set 后回读
dart run tool/verify_player_info_live.dart # 无 GPU 时降级退出 0

# 发版校验（CI 也会跑）
python tool/ci_release.py version
python tool/ci_release.py check-tag v0.1.0
python tool/ci_release.py release-body 0.1.0
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

### G. 截图脚本的坐标偏移（务必记住）

`.probe/measure.py` 已不在仓库；现在用 `.probe/shot_win.py <title> <out>`
（PrintWindow + `PW_RENDERFULLCONTENT`，不依赖前台，被遮挡也能截）或
`.probe/shot_client.py`。窗口仍被摆到 `(-8, -8, w+16, h+16)` 附近，Windows 无边框窗口的
不可见边框是 **左/右/下各 8、上 0**，所以坐标口径与旧 `measure.py` 相同：

- 客户区实际顶部落在**屏幕 y = -8**，横向落在 x = 0。
- 截图裁掉四周 8 后，图上的 y 比 Flutter 逻辑 y **小 8**，x 与逻辑坐标一致。
- 真实鼠标点击用屏幕坐标，因此 **screen y = 逻辑 y − 8**。

也就是说：截图上量到分隔线在 52，对应逻辑 60（顶栏 60 高）；要点逻辑 y=318 的
侧栏项，就点屏幕 310。表 E/F 与本文件里的实测值都是**截图坐标**，可直接和新图对齐。

点击用 `.probe/click_at.py <title> <x> <y>`：先 HWND_TOPMOST 置顶再真实鼠标点击。
**复刻版从后台 shell 启动时真实鼠标点击仍可能不生效**（前台抢占被拒，表现为"点了没反应"），
交互回归以 widget/e2e 测试为准；真机截图只用于「页面渲染了真实数据」这种静态证据。
同理，**文字输入**不能用 `SendKeys`（CJK 会丢），也别往顶层 HWND 发 `WM_CHAR`；
要么 `SendInput + KEYEVENTF_UNICODE`（需前台），要么向 `FLUTTERVIEW` 子窗口
PostMessage `WM_CHAR(ord(ch))`（不需要前台）。

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
