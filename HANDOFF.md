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
| Phase 2 — 源接入（灵魂） | ⬜ 未开始（需联网 + 原版二进制） |
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
- **44 个测试全绿**（`store_test` 30 + `search_test` 6 + `assets_test` 3 +
  `widget_test` 5）、`flutter analyze` 零问题

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
    store.dart              AppStore（数据读写 + seed + 各 getter）
    demo_data.dart          演示片单（截图里的真实内容）+ detailDemo
    search.dart             搜索结果模型 + searchCatalogue()（Phase 2 换真实站点搜索）
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

### 🟡 Phase 2 — 源接入（灵魂，未开始）
- 猫源宿主：Node.js + fastify，实现 `catServerFactory`/`catDartServerPort`/`messageToDart`/
  `js2p://_WEB_` 协议
- TVBox：CPython + JS spider（参考原版 `py_host`/`spider_channel`）
- 挂载：Emby/WebDAV/AList/网盘
- 可用性度量：不只判 `supported`，补 `latencyMs`/`movieCount`/`checkedAt`
- ⚠️ 依赖原版包 `node/`、`python/` 二进制 + 联网，**不适合无人值守推进**

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
flutter test                    # 冒烟测试（当前 44 个全绿）
flutter analyze                 # 静态检查（当前零问题）
dart run tool/verify_toolchain.dart  # 校验 SDK 版本对齐
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

1. **让用户验收这一轮**（详情页 + 搜索页）：
   - 详情页：五个入口（首页续播卡 / 分区海报 / hero「详情」/ 收藏网格 / 历史行）进去，
     看 hero 尺寸、`继续 第N集`、分页高亮、电影隐藏选集、收藏写库、返回停原页。
   - 搜索页：点顶栏搜索框或按 `Ctrl+K`，看空态文案；输入「尚」看联想；
     回车看分组 chip 与结果行；点 `严格` 看是否只剩精确匹配；点右下圆钮 / 顶栏网格图标
     看「搜索哪些资源」弹窗；`取消` 或 `Esc` 回到原来的页面。
2. 验收无误后由**用户自己**推送（AI 不 push）：`git push -u origin master`。
3. Phase 1 只剩「设置页媒体徽章子页」一个纯本地小项，其余都要 Phase 2 之后。
4. Phase 2 起必须用户在场 + 联网 + 原版二进制（Node/Python/mpv），不适合无人值守推进。

---

## 十、历史背景速查

- 原版缺陷清单、依赖清单（liquid_glass_widgets/media_kit/fvp/canvas_danmaku 等）、
  i18n 功能面（210 键反推）、明文脚本参考（`../.probe/bcl106-hosts/`）→ 见 `ARCHITECTURE.md` 附录。
- 更细的工作日志 → `.workbuddy/memory/2026-11-20.md` 和 `topics/rebuild.md`。
- 完整对话记录 → `C:\Users\lxy\.workbuddy\projects\e-code-AndroidProjects-FengMi\2d03b581-3772-42d5-8007-9c2e060e7cc0.jsonl`
