import 'package:file_selector/file_selector.dart'
    show XTypeGroup, openFile;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/badge_rule.dart';
import '../../services/danmaku/danmaku_api.dart';
import '../../services/icon_packs.dart';
import '../../services/store.dart';
import '../../services/track_choice.dart';
import '../../services/widgets/widget_center.dart';
import '../page_header.dart';
import '../custom/widgets_settings_page.dart';
import '../widgets/backup_dialog.dart';
import '../widgets/kernel_dialog.dart';
import '../widgets/subtitle_sites_settings.dart';
import '../widgets/subtitle_style.dart';

/// Settings root + the sub-pages reachable from it.
///
/// Structure, wording and metrics come from the original 1.0.6 build. The root
/// lists the top-level groups; tapping a row pushes a sub-page (外观, 首页与导航,
/// 搜索与输入, 播放, 媒体徽章 …). Rows are 70px tall with a 36px tinted icon
/// disc, a 17px title and a 13.5px subtitle. Sub-page rows are structural
/// placeholders — the wording mirrors the original's i18n keys but the toggles
/// and pickers are not wired yet.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _title = '设置';

  /// Null on the root list; otherwise the id of the active sub-page.
  String? _sub;

  /// 上一级 sub 页，最外层压着 null（根列表）。
  ///
  /// 原版的设置是逐级 push 的：播放 → 字幕 的返回该回到「播放」，而不是一步
  /// 跳回根列表。只有一个 `_sub` 时做不到这一点。
  final List<String?> _parents = [];

  void _open(String sub) {
    _parents.add(_sub);
    setState(() => _sub = sub);
    LcbPageHeaderScope.of(context).push(sub, _back, showSearch: false);
  }

  void _back() {
    if (!mounted) return;
    final parent = _parents.isEmpty ? null : _parents.removeLast();
    setState(() => _sub = parent);
    if (parent == null) {
      LcbPageHeaderScope.of(context).reset(_title);
    } else {
      LcbPageHeaderScope.of(context).push(parent, _back, showSearch: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) => ScrollConfiguration(
        behavior: ScrollConfiguration.of(context)
            .copyWith(scrollbars: false),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            LcbMetrics.settingsPaddingLeft,
            // Sub-pages have no group label, so they need the label's height as
            // extra top padding to keep the first card in the same place.
            _sub != null ? 35 : 8,
            LcbMetrics.settingsPaddingRight,
            40,
          ),
          children: _sub != null ? _subRows(_sub!, store) : _rootRows(store),
        ),
      ),
    );
  }

  List<Widget> _rootRows(AppStore store) => [
        const _GroupLabel('通用'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.wand_stars,
              color: LcbColors.sysIndigo,
              title: '外观',
              subtitle: '深浅色、强调色、液态玻璃、状态栏',
              value: '自动',
              onTap: () => _open('外观'),
            ),
            _Row(
              icon: CupertinoIcons.house_fill,
              color: LcbColors.sysOrange,
              title: '首页与导航',
              subtitle: '导航栏、首页入口、轮播海报',
              onTap: () => _open('首页与导航'),
            ),
            _Row(
              icon: CupertinoIcons.square_grid_2x2_fill,
              color: LcbColors.sysGreen,
              title: '组件',
              subtitle: '导入组件仓库，搭建自定义首页页面',
              value: '${WidgetCenter.repos(store).length} 个仓库',
              onTap: () => _open('组件'),
            ),
            _Row(
              icon: CupertinoIcons.search,
              color: LcbColors.sysBlue,
              title: '搜索与输入',
              subtitle: '平台列表布局、聚合搜索、遥控器键盘',
              onTap: () => _open('搜索与输入'),
            ),
            _Row(
              icon: CupertinoIcons.play_rectangle_fill,
              color: LcbColors.sysPink,
              title: '播放',
              subtitle: '手势、弹幕、倍速、字幕、短剧预载',
              onTap: () => _open('播放'),
            ),
            _Row(
              icon: CupertinoIcons.rosette,
              color: LcbColors.sysPurple,
              title: '媒体徽章',
              subtitle: '4K、杜比、HDR 等规格徽章的开关、显示位置和徽章包',
              value: '内置',
              onTap: () => _open('媒体徽章'),
            ),
          ],
        ),
        const SizedBox(height: 23),
        const _GroupLabel('账号与服务'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.person_crop_circle_fill,
              color: LcbColors.sysBlueDark,
              title: '账号管理',
              subtitle: 'TMDB、服务代理、Trakt、Bangumi、豆瓣',
              value: '未登录',
              onTap: () => _open('账号管理'),
            ),
            _Row(
              icon: CupertinoIcons.sparkles,
              color: LcbColors.sysViolet,
              title: 'AI 大模型',
              subtitle: '集名净化、Py 源安全检测、字幕翻译',
              value: '未配置',
              onTap: () => _open('AI 大模型'),
            ),
            _Row(
              icon: CupertinoIcons.tv_fill,
              color: LcbColors.sysGreen,
              title: 'TVBox 功能',
              subtitle: '扫码输入、扫码控制、同步配置、网页端',
              onTap: () => _open('TVBox 功能'),
            ),
            _Row(
              icon: CupertinoIcons.tag_fill,
              color: LcbColors.sysOrange,
              title: '推送识别',
              subtitle: '打开分享、剪贴板或其他设备推来的链接',
              onTap: () => _open('推送识别'),
            ),
            _Row(
              icon: CupertinoIcons.link,
              color: LcbColors.sysPurple,
              title: '猫源配置与网盘登录',
              subtitle: '打开源的配置网页，扫码登录网盘',
              onTap: () => _open('猫源配置与网盘登录'),
            ),
          ],
        ),
        const SizedBox(height: 23),
        const _GroupLabel('数据'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.archivebox_fill,
              color: LcbColors.sysGray,
              title: '数据与存储',
              subtitle: '备份恢复、下载管理、缓存与观看历史',
              // The only group whose numbers are real, so it opens instead of
              // sitting as a placeholder.
              value: '${store.sources.length} 个源',
              onTap: () => _open('数据与存储'),
            ),
          ],
        ),
        const SizedBox(height: 23),
        const _GroupLabel('关于'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.doc_text_fill,
              color: LcbColors.sysIndigo,
              title: '用户协议',
              onTap: () => _open('用户协议'),
            ),
            _Row(
              icon: CupertinoIcons.chart_bar_alt_fill,
              color: LcbColors.sysGreen,
              title: '匿名启动统计',
              subtitle: '启动时只报一个随机安装编号、版本和平台，用来统计每天、每月有多少人在用',
              toggle: true,
              toggleValue: store.settings.startupStats,
              onToggle: (value) => store.updateSettings(
                store.settings.copyWith(startupStats: value),
              ),
            ),
            _Row(
              icon: CupertinoIcons.bell_circle_fill,
              color: LcbColors.sysOrange,
              title: '启动时弹出通知',
              subtitle: '关闭后启动时不再弹窗（包括更新提示），通知仍可在“历史通知”里查看',
              toggle: true,
              toggleValue: store.settings.startupNotify,
              onToggle: (value) => store.updateSettings(
                store.settings.copyWith(startupNotify: value),
              ),
            ),
            _Row(
              icon: CupertinoIcons.bell_solid,
              color: LcbColors.sysRed,
              title: '历史通知',
              onTap: () => _open('历史通知'),
            ),
            _Row(
              icon: CupertinoIcons.chat_bubble_2_fill,
              color: LcbColors.sysSky,
              title: '联系我们',
              subtitle: 'QQ 群 1081010521 · 点击加群，长按复制群号',
              onTap: () => _open('联系我们'),
            ),
          ],
        ),
        const _VersionFooter(),
      ];

  /// Dispatches the active sub-page to its row builder. New sub-pages add a
  /// case here; unknown ids fall back to an empty card so the back button still
  /// works while a page is being wired up.
  List<Widget> _subRows(String sub, AppStore store) {
    switch (sub) {
      case '外观':
        return _appearanceRows(store);
      case '首页与导航':
        return _homeNavRows(store);
      case '搜索与输入':
        return _searchInputRows(store);
      case '播放':
        return _playbackRows(store);
      case '字幕':
        return _subtitleRows(store);
      case '字幕网站':
        return const [SubtitleSitesSettings()];
      case '弹幕':
        return _danmakuRows(store);
      case '弹幕源':
        return _danmakuSourceRows(store);
      case '组件':
        return const [CustomPagesSettings()];
      case '媒体徽章':
        return _badgeRows(store);
      case '数据与存储':
        return _dataRows(store);
      case '源图标包':
        return const [_IconPacksSection()];
      case '自定义页面':
        return const [CustomPagesSettings()];
      case '账号管理':
        return _infoRows(
          '账号管理',
          'TMDB API Key 在「搜索与输入 → TMDB」里填写；Trakt / Bangumi / 豆瓣 账号与接口尚未接入，不显示未经验证的登录状态。',
        );
      case 'AI 大模型':
        return _infoRows(
          'AI 大模型',
          '集名净化、Py 源安全检测与字幕翻译需要真实模型接口；当前未配置，不调用也不编造结果。',
        );
      case 'TVBox 功能':
        return _infoRows(
          'TVBox 功能',
          '扫码输入、扫码控制、同步配置与网页端依赖网关服务；当前没有已连接的设备。',
        );
      case '推送识别':
        return _infoRows(
          '推送识别',
          '打开分享、剪贴板或其他设备推来的链接需要系统分享与设备发现权限；当前未接入。',
        );
      case '猫源配置与网盘登录':
        return _infoRows(
          '猫源配置与网盘登录',
          '源的配置网页由当前猫源提供；没有可用的配置地址时不打开空白页。',
        );
      case '用户协议':
        return _infoRows('用户协议', '当前构建没有捆绑用户协议文本，不显示占位内容。');
      case '历史通知':
        return _infoRows('历史通知', '还没有收到过通知；原版会在这里列出更新与追更提醒。');
      case '联系我们':
        return _infoRows(
          '联系我们',
          'QQ 群 1081010521 · 点击加群，长按复制号码。当前构建不自动拉起 QQ。',
        );
      default:
        return const [];
    }
  }

  List<Widget> _infoRows(String title, String note) => [
    _Group(
      rows: [
        _Row(icon: CupertinoIcons.info_circle, color: LcbColors.sysBlue, title: title, subtitle: note),
      ],
    ),
  ];

  Future<void> _showAiTranslationSettings() async {
    final store = StoreScope.of(context);
    await showDialog<void>(
      context: context,
      builder: (_) => _AiTranslationDialog(store: store),
    );
  }

  Future<void> _showKernelDialog() async => showKernelDialog(context);

  Future<void> _showKernelSettings() async {
    final store = StoreScope.of(context);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('内核设置'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'mpv',
                style: TextStyle(fontSize: 14, color: LcbColors.text),
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('硬件解码'),
                subtitle: const Text(
                  '开：hwdec=auto-safe；关：hwdec=no。花屏或黑屏时关掉再播。',
                  style: TextStyle(fontSize: 11.5),
                ),
                value: store.settings.decoderMode != 'software',
                onChanged: (value) => store.updateSettings(
                  store.settings.copyWith(
                    decoderMode: value ? 'hardware' : 'software',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Future<void> _setTmdbKey() async {
    final store = StoreScope.of(context);
    final key = await showDialog<String>(
      context: context,
      builder: (_) => _ApiKeyDialog(current: store.settings.tmdbApiKey),
    );
    if (key == null) return;
    await store.updateSettings(store.settings.copyWith(tmdbApiKey: key.trim()));
    if (!mounted) return;
    _toast(key.trim().isEmpty ? 'TMDB API Key 已清除' : 'TMDB API Key 已保存');
  }

  String _themeModeLabel(String mode) {
    switch (mode) {
      case 'dark':
        return '深色';
      case 'light':
        return '浅色';
      default:
        return '自动';
    }
  }

  String _languageLabel(String lang) {
    switch (lang) {
      case 'en':
        return 'English';
      case 'zh-TW':
        return '繁體中文';
      default:
        return '简体中文';
    }
  }

  // ---------------------------------------------------------------------------
  // 数据与存储
  // ---------------------------------------------------------------------------

  /// The original's seven rows in its order, with every number read from the
  /// store. 本机数据 on top is ours -- the original has no summary row -- because
  /// "1 个源 · 59 个站点" is the one place a user sees what this install holds.
  List<Widget> _dataRows(AppStore store) => [
        const _GroupLabel('数据'),
        _Group(
          rows: [
            _Row(
              icon: Icons.key,
              color: LcbColors.sysBlue,
              title: '填写 TMDB API Key',
              subtitle: '只保存在本机，不进备份；留空保存即清除',
              value: store.settings.tmdbApiKey.isEmpty ? '未设置' : '已设置',
              onTap: _setTmdbKey,
            ),
            _Row(
              icon: CupertinoIcons.chart_pie_fill,
              color: LcbColors.sysPurple,
              title: '本机数据',
              subtitle:
                  '${store.sources.length} 个源 · '
                  '${store.activeSites.length}/${store.siteCount} 个启用站点 · '
                  '${store.favorites.length} 条收藏 · '
                  '${store.history.length} 条历史',
              value: '${store.siteCount} 个站点',
            ),
            _Row(
              icon: CupertinoIcons.archivebox_fill,
              color: LcbColors.sysOrange,
              title: '备份与恢复',
              subtitle: '把源、站点开关、收藏和观看历史导出成文件，或从文件恢复',
              onTap: () => showBackupDialog(context, store),
            ),
            _Row(
              icon: CupertinoIcons.arrow_down_circle_fill,
              color: LcbColors.sysBlue,
              title: '下载管理',
              subtitle: '正在下载与已完成的任务',
              // Nothing can be downloaded until playback resolves a real URL, so
              // this stays an honest zero rather than a fabricated count.
              value: '0 个',
              onTap: () => _toast('下载要等播放链路接上真实地址后才能做'),
            ),
            _Row(
              icon: CupertinoIcons.settings,
              color: LcbColors.sysTeal,
              title: '下载设置',
              subtitle: '常规设置 m3u8 分片、同时下载数、限速、重试',
              onTap: () => _toast('下载设置要等下载功能落地'),
            ),
            _Row(
              icon: CupertinoIcons.square_stack_3d_down_right,
              color: LcbColors.sysPurple,
              title: '源图标包',
              subtitle: '导入、合并或删除 ZIP 图标包',
              onTap: () => _open('源图标包'),
            ),
            _Row(
              icon: CupertinoIcons.photo,
              color: LcbColors.sysGray,
              title: '清除图片缓存',
              subtitle: '海报与头像的本地缓存',
              // Posters are generated gradients plus bundled fixture art, so
              // there is no on-disk cache to clear -- the number is truly zero.
              value: '0 KB',
              onTap: () => _toast('当前没有可清除的图片缓存'),
            ),
            _Row(
              icon: CupertinoIcons.bubble_left_fill,
              color: LcbColors.sysSky,
              title: '清理 TMDB 缓存',
              subtitle: '网络数据占满给标题与 TMDB 资料；清理后下次打开会重新刷新',
              value: '0 KB',
              onTap: () => _toast('没有 TMDB 缓存：片单还没走真实接口'),
            ),
            _Row(
              icon: CupertinoIcons.time,
              color: LcbColors.sysRed,
              title: '清空观看历史',
              subtitle: store.history.isEmpty
                  ? '历史已经空了'
                  : '清空后首页的「继续观看」也会一起收起',
              value: '${store.history.length} 条',
              onTap: () => _clearHistory(store),
            ),
          ],
        ),
      ];

  /// The toggle's subtitle tells the truth about what will happen: an unset
  /// duration means nothing is skipped even with the switch on.
  /// Empties the watch history after a confirmation, so the row's count, the
  /// history page and the home rail all drop to zero together.
  Future<void> _clearHistory(AppStore store) async {
    final count = store.history.length;
    if (count == 0) {
      _toast('观看历史已经是空的');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x78000000),
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          '清空观看历史？',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '共 $count 条，清空后无法恢复（收藏不受影响）。',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清空', style: TextStyle(color: LcbColors.sysRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.clearHistory();
    if (!mounted) return;
    _toast('已清空 $count 条观看历史');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  List<Widget> _appearanceRows(AppStore store) => [
        _Group(
          rows: [
            _Row(
              icon: Icons.contrast,
              color: LcbColors.sysIndigo,
              title: '外观模式',
              value: _themeModeLabel(store.settings.themeMode),
              onTap: () {},
            ),
            _Row(
              icon: Icons.water_drop_outlined,
              color: LcbColors.sysBlue,
              title: '强调色',
              dot: LcbColors.primary,
              onTap: () {},
            ),
            _Row(
              icon: Icons.image_outlined,
              color: LcbColors.sysGreen,
              title: '自定义背景',
              value: '未设置',
              onTap: () {},
            ),
            _Row(
              icon: Icons.translate,
              color: LcbColors.sysBlue,
              title: '语言',
              value: _languageLabel(store.settings.language),
              onTap: () {},
            ),
            _Row(
              icon: Icons.text_fields,
              color: LcbColors.sysGray,
              title: '字体与字号',
              onTap: () {},
            ),
            _Row(
              icon: Icons.palette_outlined,
              color: LcbColors.sysPurple,
              title: '自适应颜色',
              subtitle: '首页配色跟随顶部推荐封面的主色',
              toggle: true,
              toggleValue: store.settings.adaptiveColor,
              onToggle: (v) =>
                  store.updateSettings(store.settings.copyWith(adaptiveColor: v)),
            ),
            _Row(
              icon: Icons.blur_on,
              color: LcbColors.sysTeal,
              title: '液态玻璃',
              subtitle: '关闭后底栏与悬浮按钮使用纯色',
              toggle: true,
              toggleValue: store.settings.liquidGlass,
              onToggle: (v) =>
                  store.updateSettings(store.settings.copyWith(liquidGlass: v)),
            ),
            _Row(
              icon: Icons.tv,
              color: LcbColors.sysBlue,
              title: '电视模式',
              subtitle: '顶部导航、遥控器方向键操作；盒子没被识别成电视时手动开启',
              value: '自动（非电视）',
              onTap: () {},
            ),
            _Row(
              icon: Icons.auto_fix_high_outlined,
              color: LcbColors.sysPurple,
              title: '隐藏状态栏',
              subtitle: '让首页封面延伸到屏幕顶端',
              toggle: true,
              toggleValue: store.settings.hideStatusBar,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(hideStatusBar: v),
              ),
            ),
          ],
        ),
      ];

  /// 首页与导航 — home carousel, home categories and the navigation bar.
  List<Widget> _homeNavRows(AppStore store) => [
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.list_bullet,
              color: LcbColors.sysOrange,
              title: '导航栏',
              subtitle: '入口顺序、首页位置、底部行为',
              value: '5 个入口',
              onTap: () => _toast('侧栏固定为 首页 / 资源 / 收藏 / 历史 / 设置'),
            ),
            _Row(
              icon: CupertinoIcons.rectangle_grid_2x2,
              color: LcbColors.sysBlue,
              title: '首页布局',
              subtitle: '调整首页区域顺序和显示方式',
              onTap: () => _toast('首页布局由自定义页面控制，可在「组件」里编辑'),
            ),
            _Row(
              icon: CupertinoIcons.textformat_size,
              color: LcbColors.sysTeal,
              title: '首页平台参数配置',
              subtitle: '控制首页平台名显示宽度',
              value: '10 字',
              onTap: () => _toast('平台名按 10 字宽度截断'),
            ),
            _Row(
              icon: CupertinoIcons.photo_fill_on_rectangle_fill,
              color: LcbColors.sysGreen,
              title: '首页轮播海报',
              subtitle: '顶部自动轮播的推荐海报',
              toggle: true,
              toggleValue: store.settings.homeBannerEnabled,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(homeBannerEnabled: v),
              ),
            ),
            _Row(
              icon: CupertinoIcons.square_on_square,
              color: LcbColors.sysPurple,
              title: '第二媒体桌面',
              subtitle: '首页重复内容按不同规则展示，可在首页长按切换',
              toggle: true,
              toggleValue: store.settings.secondHome,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(secondHome: v),
              ),
            ),
          ],
        ),
      ];

  /// 搜索与输入 — platform layout, aggregate search and the remote keyboard.
  List<Widget> _searchInputRows(AppStore store) => [
        const _GroupLabel('搜索'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.rectangle_grid_2x2,
              color: LcbColors.sysBlue,
              title: '平台列表布局',
              subtitle: '搜索结果按平台分组时的展示方式',
              value: store.settings.platformListLayout == 'preset2'
                  ? '预设两列'
                  : '单列',
              onTap: () => store.updateSettings(
                store.settings.copyWith(
                  platformListLayout:
                      store.settings.platformListLayout == 'preset2'
                      ? 'single'
                      : 'preset2',
                ),
              ),
            ),
            _Row(
              icon: CupertinoIcons.search,
              color: LcbColors.sysGreen,
              title: '聚合搜索',
              subtitle: '当前在没选具体平台时，同时搜索全部有资源',
              value: store.settings.aggregateSearch ? '开启' : '关闭',
              onTap: () => store.updateSettings(
                store.settings.copyWith(
                  aggregateSearch: !store.settings.aggregateSearch,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 23),
        const _GroupLabel('输入'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.keyboard,
              color: LcbColors.sysIndigo,
              title: '遥控器键盘',
              subtitle:
                  '字符输入自动切换成精简输入，支持拼音全拼输入、英文、数字；'
                  '数字字母键盘可让输入更准确；遥控器上输入更轻松。',
              value: store.settings.tvKeyboard ? '开启' : '关闭',
              onTap: () => store.updateSettings(
                store.settings.copyWith(
                  tvKeyboard: !store.settings.tvKeyboard,
                ),
              ),
            ),
          ],
        ),
      ];

  List<Widget> _playbackRows(AppStore store) => [
        const _GroupLabel('播放器内核'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.play_rectangle_fill,
              color: LcbColors.sysGreen,
              title: '默认内核',
              subtitle: 'MPV、IJK、EXO 等播放内核',
              value: 'MPV',
              onTap: _showKernelDialog,
            ),
            _Row(
              icon: CupertinoIcons.person_crop_square_fill,
              color: LcbColors.sysBlue,
              title: '默认解码',
              subtitle: '当前内核的硬件解码方式',
              value: store.settings.decoderMode == 'software'
                  ? '软件解码'
                  : '硬件解码',
              onTap: () => store.updateSettings(
                store.settings.copyWith(
                  decoderMode: store.settings.decoderMode == 'software'
                      ? 'hardware'
                      : 'software',
                ),
              ),
            ),
            _Row(
              icon: CupertinoIcons.slider_horizontal_3,
              color: LcbColors.sysOrange,
              title: '内置设置',
              subtitle: '当前内核的画质、硬解、缓存与日志设置',
              onTap: _showKernelSettings,
            ),
            _Row(
              icon: CupertinoIcons.arrow_2_squarepath,
              color: LcbColors.sysTeal,
              title: '播放失败自动切换内核',
              subtitle: '打开内核的自动切换，下一集仍以默认内核播放',
              toggle: true,
              toggleValue: store.settings.autoSwitchKernel,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(autoSwitchKernel: v),
              ),
            ),
            _Row(
              icon: CupertinoIcons.arrow_right_arrow_left,
              color: LcbColors.sysGreen,
              title: '播放失败自动切换线路/来源',
              subtitle: '视频打不开时按顺序尝试下一个线路或来源',
              toggle: true,
              toggleValue: store.settings.autoSwitchSource,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(autoSwitchSource: v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 23),
        const _GroupLabel('播放设置'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.rectangle_grid_1x2,
              color: LcbColors.sysPurple,
              title: '直播切换样式',
              subtitle: '频道切换时的提示样式',
              value: store.settings.liveSwitchStyle == 'text' ? '文字' : '图标',
              onTap: () => store.updateSettings(
                store.settings.copyWith(
                  liveSwitchStyle: store.settings.liveSwitchStyle == 'text'
                      ? 'icon'
                      : 'text',
                ),
              ),
            ),
            _Row(
              icon: CupertinoIcons.rectangle_on_rectangle,
              color: LcbColors.sysTeal,
              title: '韩国版视频布局',
              subtitle: '另外用两种架构显示，上线后还是这样显示',
              value: store.settings.koreanVideoLayout ? '开启' : '关闭',
              onTap: () => store.updateSettings(
                store.settings.copyWith(
                  koreanVideoLayout: !store.settings.koreanVideoLayout,
                ),
              ),
            ),
            _Row(
              icon: CupertinoIcons.globe,
              color: LcbColors.sysBlue,
              title: '浏览器 UA',
              subtitle:
                  '默认（与运行平台匹配）；有的资源要求特定标识才给视频播放地址',
              value: store.settings.browserUA.isEmpty
                  ? '默认（与运行平台匹配）'
                  : store.settings.browserUA,
              onTap: () => _toast('浏览器 UA 尚未提供编辑入口'),
            ),
            _Row(
              icon: CupertinoIcons.play_circle,
              color: LcbColors.sysGreen,
              title: '后台播放',
              subtitle: '熄屏或切换到别的应用以后继续播放，可在通知栏控制',
              toggle: true,
              toggleValue: store.settings.backgroundPlay,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(backgroundPlay: v),
              ),
            ),
            _Row(
              icon: CupertinoIcons.settings,
              color: LcbColors.sysGray,
              title: '继承显示系统代理',
              subtitle:
                  '只对打开更新、配置页面与网页资源生效；自动启动播放打开网页时避免重复设置',
              toggle: true,
              toggleValue: store.settings.inheritSystemProxy,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(inheritSystemProxy: v),
              ),
            ),
          ],
        ),
      ];

  List<Widget> _subtitleRows(AppStore store) => [
        const _GroupLabel('默认'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.captions_bubble,
              color: LcbColors.sysPink,
              title: '默认字幕',
              subtitle: '新开一集时先选这一种；播放页点过的那条永远优先',
              value: _subtitlePrefLabel(store.settings.subtitlePref),
              onTap: () => _pickSubtitlePref(store),
            ),
            _Row(
              icon: CupertinoIcons.textformat_size,
              color: LcbColors.sysIndigo,
              title: '字号',
              subtitle: '字幕文字大小，改完立刻生效',
              value:
                  '${LcbSubtitleStyle.labelOf(store.settings.subtitleSize)} '
                  '${store.settings.subtitleSize}',
              onTap: () => _pickSubtitleSize(store),
            ),
            _Row(
              icon: CupertinoIcons.sparkles,
              color: LcbColors.sysPurple,
              title: 'AI 翻译',
              subtitle: 'OpenAI 兼容接口；Key 只保存在本机，不进备份',
              onTap: _showAiTranslationSettings,
            ),
            _Row(
              icon: CupertinoIcons.globe,
              color: LcbColors.sysPink,
              title: '字幕网站',
              subtitle: '配好搜索地址，播放时可以直接搜字幕挂到本集',
              onTap: () => _open('字幕网站'),
            ),
            _Row(
              icon: CupertinoIcons.rectangle_on_rectangle_angled,
              color: LcbColors.sysTeal,
              title: '次字幕',
              subtitle: '显示在画面上方，和主字幕组成双语对照',
              value: SecondarySubtitle.parse(
                store.settings.secondarySubtitle,
              ).label,
              onTap: () => _pickSecondarySubtitle(store),
            ),
          ],
        ),
        const SizedBox(height: 23),
        const _GroupLabel('每部剧的选择'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.memories,
              color: LcbColors.sysOrange,
              title: '记住的轨道选择',
              subtitle: store.trackPrefCount == 0
                  ? '在播放页换过画质、音轨或字幕的线路会记在这里'
                  : '这些线路下次打开还是你上次选的那几条',
              value: store.trackPrefCount == 0 ? '无' : '${store.trackPrefCount} 条',
              onTap: () => _clearTrackPrefs(store),
            ),
            _Row(
              icon: CupertinoIcons.doc_text,
              color: LcbColors.sysGreen,
              title: '记着的外挂字幕',
              subtitle: store.externalSubtitleCount == 0
                  ? '在播放页的轨道面板里选过本地字幕的集会记在这里'
                  : '这些集下次打开会自己挂上同一个文件',
              value: store.externalSubtitleCount == 0
                  ? '无'
                  : '${store.externalSubtitleCount} 集',
              onTap: () => _clearExternalSubtitles(store),
            ),
          ],
        ),
        const SizedBox(height: 23),
        const _Note(
          '「默认字幕」只在一条线路还没有你的选择时生效。在播放页右下角的轨道'
          '面板里点过任何一条（包括「关闭」），那部剧就按你点的来，不会再被这里'
          '的默认值改回去。次字幕是另一条轨，挑不到就只显示主字幕。',
        ),
      ];

  /// 弹幕 — 开关、屏蔽区，以及去管弹幕源。
  ///
  /// 匹配走「片名 + 集数」，所以播放页不需要文件哈希也能问到；`实际能拿到多少
  /// 条` 由播放页底栏报（`弹幕 12`），这一页只负责配置。
  List<Widget> _danmakuRows(AppStore store) {
    final sources = store.danmakuSources;
    final custom = store.customDanmakuSourceCount;
    final enabledCount = sources.where((s) => s.enabled).length;
    return [
      const _GroupLabel('显示'),
      _Group(
        rows: [
          _Row(
            icon: CupertinoIcons.chat_bubble_2_fill,
            color: LcbColors.sysTeal,
            title: '显示弹幕',
            subtitle: '总开关；关掉后弹幕按钮也不再向弹幕源发请求。每次进播放页仍默认关闭',
            toggle: true,
            toggleValue: store.settings.danmakuEnabled,
            onToggle: (v) => store.updateSettings(
              store.settings.copyWith(danmakuEnabled: v),
            ),
          ),
          _Row(
            icon: Icons.vertical_align_top,
            color: LcbColors.sysIndigo,
            title: '屏蔽顶部弹幕',
            subtitle: '顶部固定弹幕会挡住画面，滚动的不受影响',
            toggle: true,
            toggleValue: store.settings.danmakuBlockTop,
            onToggle: (v) => store.updateSettings(
              store.settings.copyWith(danmakuBlockTop: v),
            ),
          ),
          _Row(
            icon: Icons.vertical_align_bottom,
            color: LcbColors.sysIndigo,
            title: '屏蔽底部弹幕',
            subtitle: '底部固定弹幕会和字幕、控制条打架',
            toggle: true,
            toggleValue: store.settings.danmakuBlockBottom,
            onToggle: (v) => store.updateSettings(
              store.settings.copyWith(danmakuBlockBottom: v),
            ),
          ),
        ],
      ),
      const SizedBox(height: 23),
      const _GroupLabel('弹幕来源'),
      _Group(
        rows: [
          _Row(
            icon: Icons.dns,
            color: LcbColors.sysBlue,
            title: '弹幕源',
            subtitle: custom == 0
                ? '内置弹弹play；也可以加自己部署的地址'
                : '内置 1 个 · 自己加的 $custom 个',
            value: enabledCount == 0 ? '都没启用' : '${sources.length} 个',
            onTap: () => _open('弹幕源'),
          ),
        ],
      ),
      const SizedBox(height: 23),
      const _Note(
        '播放时按「片名 + 集数」去问，问不到再拿拼出来的文件名匹配。'
        '一个源给出结果就不再问下一个。',
      ),
      const _Note(
        '弹弹play 官方接口要 AppId/AppSecret（到它的开发者后台申请后填进弹幕源）；'
        '自建的同构服务器一般不用。没填凭据时进播放页不会提示，也不发请求；只有主动点开弹幕才会问你填。',
      ),
    ];
  }

  /// 弹幕源列表：内置那条排第一，能改（填凭据、停用）但删不掉。
  List<Widget> _danmakuSourceRows(AppStore store) {
    final sources = store.danmakuSources;
    return [
      const _GroupLabel('已配置'),
      _Group(
        rows: [
          for (final s in sources)
            _Row(
              icon: s.isBuiltin
                  ? Icons.bolt
                  : Icons.public,
              color: s.isBuiltin ? LcbColors.sysOrange : LcbColors.sysBlue,
              title: s.name,
              subtitle: s.baseUrl,
              value: !s.enabled
                  ? '停用'
                  : s.hasCredentials
                      ? '有凭据'
                      : '无需凭据',
              onTap: () => _editDanmakuSource(store, s),
            ),
        ],
      ),
      const SizedBox(height: 23),
      _Group(
        rows: [
          _Row(
            icon: CupertinoIcons.add,
            color: LcbColors.sysGreen,
            title: '添加弹幕源',
            subtitle: '一个 dandanplay 兼容的服务地址',
            onTap: () => _editDanmakuSource(store, null),
          ),
        ],
      ),
      const SizedBox(height: 23),
      const _Note(
        '接口只用三个：`/api/v2/search/episodes` 按片名集数找、`/api/v2/match` '
        '按文件名找、`/api/v2/comment/{id}` 取弹幕。所以任何实现了这三个接口的'
        '自建服务都能填进来。',
      ),
    ];
  }

  /// 新增（[source] 为 null）或编辑一条弹幕源。
  ///
  /// 内置源也能编辑——填凭据、临时停用——但对话框不给删除按钮：删掉之后
  /// 播放页就一个可问的地址都没有了，不如让它只能被停用。
  Future<void> _editDanmakuSource(
    AppStore store,
    DanmakuSource? source,
  ) async {
    final result = await showDialog<Object>(
      context: context,
      builder: (_) => _DanmakuSourceDialog(source: source),
    );
    if (!mounted || result == null) return;
    if (result == 'delete') {
      if (source == null) return;
      await store.removeDanmakuSource(source.id);
      if (!mounted) return;
      _toast('已删除「${source.name}」');
      return;
    }
    if (result is! DanmakuSource) return;
    await store.saveDanmakuSource(result);
    if (!mounted) return;
    _toast(result.isBuiltin ? '已保存弹弹play 的设置' : '已保存「${result.name}」');
  }

  /// 选项上那一行字直接用 [SubtitlePref.label]——它和原版逐字一致，别在这里
  /// 另起一套叫法，两处一起看会对不上。
  String _subtitlePrefLabel(String raw) => SubtitlePref.parse(raw).short;

  Future<void> _pickSubtitlePref(AppStore store) async {
    final picked = await _choose<SubtitlePref>(
      '默认字幕',
      [
        for (final p in SubtitlePref.values)
          (value: p, label: p.label, hint: p.hint),
      ],
      isCurrent: (v) => v == SubtitlePref.parse(store.settings.subtitlePref),
    );
    if (picked == null) return;
    await store.updateSettings(store.settings.copyWith(subtitlePref: picked.slug));
    if (!mounted) return;
    _toast('默认字幕：${_subtitlePrefLabel(picked.slug)}');
  }

  /// 次字幕：和主字幕组成双语对照，显示在画面上方。
  Future<void> _pickSecondarySubtitle(AppStore store) async {
    final picked = await _choose<SecondarySubtitle>(
      '次字幕',
      [
        for (final s in SecondarySubtitle.values)
          (value: s, label: s.label, hint: s == SecondarySubtitle.off ? null : '显示在画面上方'),
      ],
      isCurrent: (v) =>
          v == SecondarySubtitle.parse(store.settings.secondarySubtitle),
    );
    if (picked == null) return;
    await store.updateSettings(
      store.settings.copyWith(secondarySubtitle: picked.slug),
    );
    if (!mounted) return;
    _toast('次字幕：${picked.label}');
  }

  Future<void> _pickSubtitleSize(AppStore store) async {
    final picked = await _choose<int>(
      '字幕字号',
      [
        for (final e in LcbSubtitleStyle.presets.entries)
          (value: e.key, label: e.value, hint: '${e.key} 像素'),
      ],
      isCurrent: (v) => v == store.settings.subtitleSize,
    );
    if (picked == null) return;
    await store.updateSettings(store.settings.copyWith(subtitleSize: picked));
    if (!mounted) return;
    _toast('字幕字号：${LcbSubtitleStyle.labelOf(picked)}（$picked）');
  }

  /// 清掉「这一集挂过哪个字幕文件」的记忆。文件本身不删——那是用户的文件。
  Future<void> _clearExternalSubtitles(AppStore store) async {
    final has = store.settings.externalSubtitles;
    if (has.isEmpty) {
      _toast('还没有哪一集记过外挂字幕');
      return;
    }
    final live = store.externalSubtitleCount;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x78000000),
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '清除外挂字幕记录？',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '共 ${has.length} 集（其中 $live 集的文件还在）。清除后这些集下次打开'
          '不会再自动挂字幕，磁盘上的字幕文件不会被删除。',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await store.clearExternalSubtitles();
    if (!mounted) return;
    _toast('已清除外挂字幕记录');
  }

  /// 清掉所有「这条线路上次选了哪条轨」的记忆，各线路回到播放器默认。
  /// 先确认：换过十条线路的人不该被一次误点清空。
  Future<void> _clearTrackPrefs(AppStore store) async {
    final count = store.trackPrefCount;
    if (count == 0) {
      _toast('还没有哪条线路记过轨道选择');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x78000000),
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '清除轨道选择？',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '共 $count 条线路。清除后下次打开这些线路，画质、音轨、字幕都回到'
          '播放器自己的默认。',
          style: const TextStyle(fontSize: 13.5, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清除', style: TextStyle(color: LcbColors.sysRed)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await store.clearTrackPrefs();
    if (!mounted) return;
    _toast('已清除 $count 条线路的轨道选择');
  }

  /// 单选弹窗：一行主文字 + 一行说明，当前值打勾。
  Future<T?> _choose<T>(
    String title,
    List<({T value, String label, String? hint})> options, {
    required bool Function(T value) isCurrent,
  }) {
    return showDialog<T>(
      context: context,
      barrierColor: const Color(0x78000000),
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final o in options)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(o.label),
                subtitle: o.hint == null || o.hint!.isEmpty
                    ? null
                    : Text(
                        o.hint!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: LcbColors.settingsQuiet,
                        ),
                      ),
                trailing: isCurrent(o.value)
                    ? const Icon(
                        Icons.check,
                        color: LcbColors.primary,
                        size: 18,
                      )
                    : null,
                onTap: () => Navigator.of(ctx).pop(o.value),
              ),
          ],
        ),
      ),
    );
  }

  /// 媒体徽章 — 4K / 杜比 / HDR specification badges, their position and
  /// which groups to show. Every value is a real setting read from the store.
  List<Widget> _badgeRows(AppStore store) => [
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.rosette,
              color: LcbColors.sysPurple,
              title: '显示媒体徽章',
              subtitle: '4K、杜比视界、HDR、DTS 等规格标签',
              toggle: true,
              toggleValue: store.settings.mediaBadgesEnabled,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(mediaBadgesEnabled: v),
              ),
            ),
            _Row(
              icon: CupertinoIcons.rectangle_3_offgrid,
              color: LcbColors.sysBlue,
              title: '显示位置',
              subtitle: '徽章摆在海报的哪个角',
              value: _badgeSpotLabel(store.settings.badgeSpot),
              onTap: () => _pickBadgeSpot(store),
            ),
            _Row(
              icon: CupertinoIcons.textformat,
              color: LcbColors.sysGreen,
              title: '带文字标签',
              subtitle: '关闭后只显示 4K、DV 这类短标',
              toggle: true,
              toggleValue: store.settings.badgeText,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(badgeText: v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 23),
        const _GroupLabel('规格'),
        _Group(
          rows: [
            for (final group in BadgeGroup.values)
              _Row(
                icon: _badgeGroupIcon(group),
                color: _badgeGroupColor(group),
                title: _badgeGroupLabel(group),
                subtitle: _badgeGroupHint(group),
                toggle: true,
                toggleValue: _badgeGroupOn(store.settings, group),
                onToggle: (v) => _setBadgeGroup(store, group, v),
              ),
          ],
        ),
        const SizedBox(height: 23),
        const _GroupLabel('徽章包'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.rectangle_stack,
              color: LcbColors.sysOrange,
              title: '徽章包',
              subtitle: '徽章的样式与图标',
              value: '内置',
              onTap: () => _toast('远端徽章包要联网下载，暂未接入'),
            ),
          ],
        ),
      ];

  String _badgeSpotLabel(String spot) {
    switch (spot) {
      case 'rightTop':
        return '右上角';
      case 'leftBottom':
        return '左下角';
      case 'rightBottom':
        return '右下角';
      case 'leftTop':
      default:
        return '左上角';
    }
  }

  Future<void> _pickBadgeSpot(AppStore store) async {
    const options = <String, String>{
      'leftTop': '左上角',
      'rightTop': '右上角',
      'leftBottom': '左下角',
      'rightBottom': '右下角',
    };
    final picked = await showDialog<String>(
      context: context,
      barrierColor: const Color(0x78000000),
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          '显示位置',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in options.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(e.value),
                trailing: store.settings.badgeSpot == e.key
                    ? const Icon(
                        Icons.check,
                        color: LcbColors.primary,
                        size: 18,
                      )
                    : null,
                onTap: () => Navigator.of(ctx).pop(e.key),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await store.updateSettings(store.settings.copyWith(badgeSpot: picked));
    if (!mounted) return;
    _toast('徽章已移到${options[picked]}');
  }

  IconData _badgeGroupIcon(BadgeGroup group) {
    switch (group) {
      case BadgeGroup.quality:
        return CupertinoIcons.arrow_up_right_square_fill;
      case BadgeGroup.hdr:
        return CupertinoIcons.sun_max_fill;
      case BadgeGroup.audio:
        return CupertinoIcons.speaker_2_fill;
      case BadgeGroup.source:
        return CupertinoIcons.cloud_fill;
    }
  }

  Color _badgeGroupColor(BadgeGroup group) {
    switch (group) {
      case BadgeGroup.quality:
        return LcbColors.sysOrange;
      case BadgeGroup.hdr:
        return LcbColors.sysViolet;
      case BadgeGroup.audio:
        return LcbColors.sysBlue;
      case BadgeGroup.source:
        return LcbColors.sysGray;
    }
  }

  String _badgeGroupLabel(BadgeGroup group) {
    switch (group) {
      case BadgeGroup.quality:
        return '画质';
      case BadgeGroup.hdr:
        return 'HDR';
      case BadgeGroup.audio:
        return '音轨';
      case BadgeGroup.source:
        return '片源';
    }
  }

  String _badgeGroupHint(BadgeGroup group) {
    switch (group) {
      case BadgeGroup.quality:
        return '4K、8K、1080p、HEVC 等分辨率与编码';
      case BadgeGroup.hdr:
        return '杜比视界、HDR10、HDR10+';
      case BadgeGroup.audio:
        return '杜比全景声、DTS、TrueHD 等音轨';
      case BadgeGroup.source:
        return 'IMAX、BluRay、WEB-DL、Remux 等片源';
    }
  }

  /// 一组规格视为「开」当且仅当组内没有任何一个 slug 被显式关掉。
  /// （缺省即开，见 [AppSettings.badgeSpecs] 的语义。）
  bool _badgeGroupOn(AppSettings settings, BadgeGroup group) {
    final slugs = BadgeRule.all.where((b) => b.group == group).map((b) => b.slug);
    return slugs.every((s) => settings.badgeSpecs[s] != false);
  }

  void _setBadgeGroup(AppStore store, BadgeGroup group, bool on) {
    final next = Map<String, bool>.from(store.settings.badgeSpecs);
    for (final b in BadgeRule.all.where((b) => b.group == group)) {
      // 开 → 删掉这条「关」的标记（回到缺省开）；关 → 显式记 false。
      if (on) {
        next.remove(b.slug);
      } else {
        next[b.slug] = false;
      }
    }
    store.updateSettings(store.settings.copyWith(badgeSpecs: next));
  }
}

/// 一节说明文字。设置页里凡是要讲清「为什么这里没有开关」的地方都用它。
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      // 说明文字不跟着卡片拉满一行：760 以内的行宽才读得动，再宽眼睛要来回扫。
      // 外面必须包一层 Align —— ListView 给子节点的是「和视口一样宽」的紧约束，
      // 直接放 ConstrainedBox 会被那对约束按回去，宽度根本收不窄。
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: LcbColors.settingsQuiet,
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 10, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: LcbColors.settingsQuiet,
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.rows});

  final List<_Row> rows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LcbColors.card,
        borderRadius: BorderRadius.circular(LcbMetrics.settingsCardRadius),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              const Divider(
                height: 1,
                thickness: 1,
                // Starts where the row's text does (icon disc 36 + gap 14 +
                // row padding 16 = 66 from the card, 106 from the gutter) and
                // stops 16px short of the trailing edge.
                indent: 106,
                endIndent: 16,
                color: LcbColors.cardDivider,
              ),
            rows[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.icon,
    required this.color,
    required this.title,
    this.subtitle,
    this.value,
    this.dot,
    this.toggle,
    this.toggleValue,
    this.onToggle,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final String? value;
  final Color? dot;

  /// Non-null renders a switch instead of the chevron.
  final bool? toggle;

  /// When non-null the switch is controlled: it shows this value and flips it
  /// via [onToggle] instead of keeping local state.
  final bool? toggleValue;

  /// Callback for a controlled switch, receives the new (flipped) value.
  final ValueChanged<bool>? onToggle;

  final VoidCallback? onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;
  bool get _isOn => widget.toggleValue ?? false;

  void _handleTap() {
    if (widget.toggle != null) {
      widget.onToggle?.call(!_isOn);
    } else {
      widget.onTap?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: Container(
          height: widget.subtitle != null
              ? LcbMetrics.settingsRowHeight
              : LcbMetrics.settingsRowCompactHeight,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: _hover ? Colors.black.withValues(alpha: 0.025) : null,
            borderRadius: BorderRadius.circular(LcbMetrics.settingsCardRadius),
          ),
          child: Row(
            children: [
              _IconDisc(icon: widget.icon, color: widget.color),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // The original's title ink sits one pixel lower inside the
                    // same box: its gap to the subtitle is 9px, ours 10.
                    Transform.translate(
                      offset: const Offset(0, 1),
                      child: Text(
                        widget.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: LcbColors.text,
                        ),
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        widget.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: LcbColors.settingsQuiet,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.value != null) ...[
                const SizedBox(width: 12),
                Text(
                  widget.value!,
                  style: const TextStyle(
                    fontSize: 14.5,
                    color: LcbColors.settingsQuiet,
                  ),
                ),
              ],
              if (widget.dot != null) ...[
                const SizedBox(width: 10),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: widget.dot,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              if (widget.toggle != null)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: _Switch(value: _isOn),
                )
              // 什么都不做的行就不画箭头：箭头是在说「点我还有下一页」。
              else if (widget.onTap != null)
                const Padding(
                  padding: EdgeInsets.only(left: 4),
                  child: Icon(
                    CupertinoIcons.chevron_forward,
                    size: 17,
                    color: LcbColors.settingsQuiet,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconDisc extends StatelessWidget {
  const _IconDisc({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: Icon(icon, size: 19, color: Colors.white),
    );
  }
}

/// The version line that closes the settings list, centred under the last card
/// in the original's muted secondary colour.
class _VersionFooter extends StatelessWidget {
  const _VersionFooter();

  @override
  Widget build(BuildContext context) {
    // The interpolated version string cannot be const.
    // ignore: prefer_const_constructors
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 8),
      // ignore: prefer_const_constructors
      child: Center(
        // ignore: prefer_const_constructors
        child: Text(
          '${LcbAppInfo.name} ${LcbAppInfo.version}（${LcbAppInfo.build}）',
          style: const TextStyle(
            fontSize: 12,
            color: LcbColors.settingsVersion,
          ),
        ),
      ),
    );
  }
}

/// iOS-style switch: 50x30 track, 26px thumb, #E2E2E2 when off and the theme's
/// muted violet when on (both sampled from the original).
class _Switch extends StatelessWidget {
  const _Switch({required this.value});

  final bool value;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: 50,
      height: 30,
      decoration: BoxDecoration(
        color: value ? LcbColors.primaryDim : LcbColors.switchOff,
        borderRadius: BorderRadius.circular(15),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Color(0x1F000000),
                  blurRadius: 2,
                  offset: Offset(0, 1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for one duration in seconds. Zero clears it.
///
/// Kept as a text field plus a few common values rather than a slider: people
/// know their show's intro is "about a minute and a half", and a slider would
/// make an exact 90 hard to hit.
class _SecondsDialog extends StatefulWidget {
  const _SecondsDialog({
    required this.title,
    required this.hint,
    required this.seconds,
  });

  final String title;
  final String hint;

  /// Current value; zero shows an empty field.
  final int seconds;

  @override
  State<_SecondsDialog> createState() => _SecondsDialogState();
}

class _SecondsDialogState extends State<_SecondsDialog> {
  /// Anything past fifteen minutes is a mis-tap, not an intro.
  static const _maxSeconds = 900;
  static const _presets = [30, 60, 90, 120, 180];

  late final TextEditingController _controller = TextEditingController(
    text: widget.seconds > 0 ? '${widget.seconds}' : '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _value {
    final parsed = int.tryParse(_controller.text.trim()) ?? 0;
    return parsed < 0 ? 0 : (parsed > _maxSeconds ? _maxSeconds : parsed);
  }

  void _submit() => Navigator.of(context).pop(_value);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: widget.hint,
                suffixText: '秒',
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final preset in _presets)
                  ActionChip(
                    label: Text('$preset 秒'),
                    onPressed: () =>
                        setState(() => _controller.text = '$preset'),
                  ),
                ActionChip(
                  label: const Text('清除'),
                  onPressed: () => setState(() => _controller.clear()),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              '留空或填 0 表示不跳。超过片长四成的设置不会生效，'
              '以免把正片当成片头跳掉。',
              style: TextStyle(fontSize: 12, color: Color(0xFF8A8A8F), height: 1.5),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

/// 弹幕源的编辑弹窗。
///
/// 只收三样：名字、地址、凭据。地址必须是 http(s) 开头——填一个 `api.xxx` 会被
/// 当场拦下，而不是等播放时抛一个 `Uri` 解析错误。凭据留空就表示"这个源不要签名"。
class _DanmakuSourceDialog extends StatefulWidget {
  const _DanmakuSourceDialog({this.source});

  /// Null means "create a new one".
  final DanmakuSource? source;

  @override
  State<_DanmakuSourceDialog> createState() => _DanmakuSourceDialogState();
}

class _DanmakuSourceDialogState extends State<_DanmakuSourceDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.source?.name ?? '');
  late final TextEditingController _base = TextEditingController(
    text: widget.source?.baseUrl ?? DanmakuSource.officialBase,
  );
  late final TextEditingController _appId =
      TextEditingController(text: widget.source?.appId ?? '');
  late final TextEditingController _secret =
      TextEditingController(text: widget.source?.appSecret ?? '');
  late bool _enabled = widget.source?.enabled ?? true;
  String? _error;

  bool get _isBuiltin => widget.source?.isBuiltin ?? false;

  @override
  void dispose() {
    _name.dispose();
    _base.dispose();
    _appId.dispose();
    _secret.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final base = _base.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '给它起个名字');
      return;
    }
    if (base.isEmpty ||
        !(base.startsWith('http://') || base.startsWith('https://'))) {
      setState(() => _error = '地址要以 http:// 或 https:// 开头');
      return;
    }
    final source = DanmakuSource(
      id: widget.source?.id ??
          's${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      name: name,
      baseUrl: DanmakuSource.stripTrailingSlash(base),
      appId: _appId.text.trim(),
      appSecret: _secret.text.trim(),
      enabled: _enabled,
    );
    Navigator.of(context).pop(source);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.source == null ? '添加弹幕源' : '编辑弹幕源',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _field(_name, '名称', hint: '例如「自建弹幕」'),
              const SizedBox(height: 12),
              _field(
                _base,
                '地址',
                hint: DanmakuSource.officialBase,
                readOnly: _isBuiltin,
              ),
              const SizedBox(height: 12),
              _field(_appId, 'AppId', hint: '没有就留空'),
              const SizedBox(height: 12),
              _field(_secret, 'AppSecret', hint: '没有就留空', obscure: true),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                title: const Text('启用', style: TextStyle(fontSize: 13.5)),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: LcbColors.sysRed,
                    height: 1.4,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              const Text(
                '凭据只存在本机，不会进备份。自建的同构服务一般不需要。',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF8A8A8F),
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.source != null && !_isBuiltin)
          TextButton(
            onPressed: () => Navigator.of(context).pop('delete'),
            child: const Text('删除', style: TextStyle(color: LcbColors.sysRed)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool obscure = false,
    bool readOnly = false,
  }) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      obscureText: obscure,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

/// 源图标包 — the originally dead row now opens a real ZIP importer.
///
/// Everything here is local: a pack never talks to the network, and an icon
/// already applied to a resource is copied out of the pack first, so deleting
/// a pack cannot break a card (原版「已经设置到资源上的图标已单独保存」).
class _IconPacksSection extends StatefulWidget {
  const _IconPacksSection();

  @override
  State<_IconPacksSection> createState() => _IconPacksSectionState();
}

class _IconPacksSectionState extends State<_IconPacksSection> {
  List<IconPack> _packs = const [];
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final packs = IconPacks.load();
    if (!mounted) return;
    setState(() => _packs = packs);
  }

  Future<void> _import() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'ZIP', extensions: ['zip']),
      ],
    );
    if (file == null) return;
    if (!mounted) return;
    setState(() => _busy = true);
    String message;
    try {
      final pack = await IconPacks.importZip(file.path);
      message = '${pack.count} 个图标 · ${pack.name}';
    } on IconPackException catch (error) {
      message = error.message;
    } on Object {
      message = '图标包读取失败';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
    await _reload();
  }

  Future<void> _rename(IconPack pack) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _IconPackNameDialog(current: pack.name),
    );
    if (name == null) return;
    try {
      await IconPacks.rename(pack.id, name);
      if (!mounted) return;
      setState(() => _message = '图标包名称已保存');
      await _reload();
    } on IconPackException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
    }
  }

  Future<void> _delete(IconPack pack) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除图标包'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('将删除这个图标包的 ${pack.count} 个图标'),
            const SizedBox(height: 8),
            Text(
              '${pack.count} 个图标。已经设置到资源上的图标已单独保存，不受影响。',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await IconPacks.delete(pack.id);
    if (!mounted) return;
    setState(() => _message = '图标包已删除');
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.square_stack_3d_down_right,
              color: LcbColors.sysPurple,
              title: '导入 ZIP 图标包',
              subtitle: '导入、命名或删除 ZIP 图标包',
              value: _busy ? '导入中' : null,
              onTap: _busy ? null : _import,
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text(
            '导入的图标包只保存在本机。编辑资源时选“图标包”，即可从这些包中选择。',
            style: TextStyle(fontSize: 13, color: LcbColors.settingsQuiet),
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: Text(
              _message!,
              key: const ValueKey('icon-pack-message'),
              style: const TextStyle(fontSize: 13, color: LcbColors.sysBlue),
            ),
          ),
        const SizedBox(height: 14),
        if (_packs.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 18),
            child: Text(
              '还没有图标包',
              style: TextStyle(fontSize: 14, color: LcbColors.settingsQuiet),
            ),
          ),
        for (final pack in _packs) ...[
          _Group(
            rows: [
              _Row(
                icon: CupertinoIcons.square_stack_3d_down_right,
                color: LcbColors.sysTeal,
                title: pack.name.isEmpty ? '未命名图标包' : pack.name,
                subtitle: '${pack.count} 个图标。名称只保存在本机，可以和 ZIP 内的建议名称不同。',
                value: '${pack.count} 个',
                onTap: () => _rename(pack),
              ),
              _Row(
                icon: CupertinoIcons.pencil,
                color: LcbColors.sysBlue,
                title: '命名图标包',
                subtitle: '只改本机显示的名字，不改图标本身',
                onTap: () => _rename(pack),
              ),
              _Row(
                icon: CupertinoIcons.trash,
                color: LcbColors.sysRed,
                title: '删除',
                subtitle: '已设置到资源上的图标不受影响',
                onTap: () => _delete(pack),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }
}

class _IconPackNameDialog extends StatefulWidget {
  const _IconPackNameDialog({required this.current});

  final String current;

  @override
  State<_IconPackNameDialog> createState() => _IconPackNameDialogState();
}

class _IconPackNameDialogState extends State<_IconPackNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.current,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('命名图标包'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '图标包名称',
          isDense: true,
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}


class _ApiKeyDialog extends StatefulWidget {
  const _ApiKeyDialog({required this.current});

  final String current;

  @override
  State<_ApiKeyDialog> createState() => _ApiKeyDialogState();
}

class _ApiKeyDialogState extends State<_ApiKeyDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('填写 TMDB API Key'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'API Key（v3）',
          isDense: true,
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('保存'),
        ),
      ],
    );
  }
}


class _AiTranslationDialog extends StatefulWidget {
  const _AiTranslationDialog({required this.store});

  final AppStore store;

  @override
  State<_AiTranslationDialog> createState() => _AiTranslationDialogState();
}

class _AiTranslationDialogState extends State<_AiTranslationDialog> {
  late final _base = TextEditingController(
    text: widget.store.settings.aiBaseUrl,
  );
  late final _model = TextEditingController(
    text: widget.store.settings.aiModel,
  );
  late final _key = TextEditingController(text: widget.store.settings.aiApiKey);
  late final _lang = TextEditingController(
    text: widget.store.settings.aiTargetLang,
  );

  @override
  void dispose() {
    _base.dispose();
    _model.dispose();
    _key.dispose();
    _lang.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('AI 翻译字幕'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _base,
              decoration: const InputDecoration(
                labelText: '接口地址',
                hintText: 'https://api.openai.com/v1',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _model,
              decoration: const InputDecoration(
                labelText: '模型',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _key,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key（可不填）',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _lang,
              decoration: const InputDecoration(
                labelText: '翻译成',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Key 只保存在本机，不进备份。内核自己画字幕时拿不到文字，AI 翻译要换成 MPV 或 Exo；本客户端用的就是 MPV。',
              style: TextStyle(fontSize: 11.5, color: LcbColors.textSecondary),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            widget.store.updateSettings(
              widget.store.settings.copyWith(
                aiBaseUrl: _base.text.trim(),
                aiModel: _model.text.trim(),
                aiApiKey: _key.text.trim(),
                aiTargetLang: _lang.text.trim().isEmpty
                    ? '简体中文'
                    : _lang.text.trim(),
              ),
            );
            Navigator.of(context).pop();
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
