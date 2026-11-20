import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../services/store.dart';
import '../page_header.dart';
import '../widgets/backup_dialog.dart';

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

  void _open(String sub) {
    setState(() => _sub = sub);
    LcbPageHeaderScope.of(context).push(sub, _back);
  }

  void _back() {
    if (!mounted) return;
    setState(() => _sub = null);
    LcbPageHeaderScope.of(context).reset(_title);
  }

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          LcbMetrics.settingsPaddingLeft,
          // Sub-pages have no group label, so they need the label's height as
          // extra top padding to keep the first card in the same place.
          _sub != null ? 35 : 8,
          LcbMetrics.settingsPaddingRight,
          40,
        ),
        children: _sub != null
            ? _subRows(_sub!, StoreScope.of(context))
            : _rootRows(StoreScope.of(context)),
      ),
    );
  }

  List<Widget> _rootRows(AppStore store) => [
        const _GroupLabel('通用'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.paintbrush_fill,
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
              value: '4 个仓库',
              onTap: () {},
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
              subtitle: '手势、弹幕、倍速、字幕、短片预载',
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
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.sparkles,
              color: LcbColors.sysViolet,
              title: 'AI 大模型',
              subtitle: '集名净化、Py 源安全检测、字幕翻译',
              value: '未配置',
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.device_phone_portrait,
              color: LcbColors.sysGreen,
              title: 'TV友好功能',
              subtitle: '扫码输入、扫码控制、同步配置、网页端',
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.link,
              color: LcbColors.sysOrange,
              title: '推送识别',
              subtitle: '打开分享、剪贴板或其他设备推来的链接',
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.globe,
              color: LcbColors.primaryDim,
              title: '猫源配置与网盘登录',
              subtitle: '打开源的配置网页，扫码登录网盘',
              onTap: () {},
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
              onTap: () {},
            ),
            const _Row(
              icon: CupertinoIcons.chart_bar_alt_fill,
              color: LcbColors.sysGreen,
              title: '匿名启动统计',
              subtitle: '启动时只报一个随机安装编号、版本和平台，用来统计每天、每月有多少人在用',
              toggle: true,
              toggleOn: true,
            ),
            const _Row(
              icon: CupertinoIcons.bell_circle_fill,
              color: LcbColors.sysOrange,
              title: '启动时弹出通知',
              subtitle: '关闭后启动时不再弹窗（包括更新提示），通知仍可在“历史通知”里查看',
              toggle: true,
              toggleOn: true,
            ),
            _Row(
              icon: CupertinoIcons.bell_solid,
              color: LcbColors.sysRed,
              title: '历史通知',
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.chat_bubble_2_fill,
              color: LcbColors.sysSky,
              title: '联系我们',
              subtitle: 'QQ 群 1081010521 · 点击加群，长按复制群号',
              onTap: () {},
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
      case '媒体徽章':
        return _badgeRows();
      case '数据与存储':
        return _dataRows(store);
      default:
        return const [];
    }
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
              onTap: () => _toast('图标包要等源图标解析完成'),
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
        const _GroupLabel('首页'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.photo_fill_on_rectangle_fill,
              color: LcbColors.sysIndigo,
              title: '首页轮播海报',
              subtitle: '顶部自动轮播的推荐海报',
              toggle: true,
              toggleValue: store.settings.homeBannerEnabled,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(homeBannerEnabled: v),
              ),
            ),
            _Row(
              icon: CupertinoIcons.square_grid_2x2_fill,
              color: LcbColors.sysOrange,
              title: '首页分类',
              subtitle: '电影、电视剧、动漫、综艺等分区',
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.clock_fill,
              color: LcbColors.sysGreen,
              title: '继续观看',
              subtitle: '首页显示上次播放到一半的内容',
              toggle: true,
              toggleValue: store.settings.secondHome,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(secondHome: v),
              ),
            ),
          ],
        ),
        const SizedBox(height: 23),
        const _GroupLabel('导航'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.list_bullet,
              color: LcbColors.sysBlue,
              title: '导航栏',
              subtitle: '侧栏分组与入口的显示',
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.tv_fill,
              color: LcbColors.sysPurple,
              title: '电视模式',
              subtitle: '顶部导航、遥控器方向键操作',
              toggle: true,
              toggleValue: store.settings.tvClassicUi,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(tvClassicUi: v),
              ),
            ),
          ],
        ),
      ];

  /// 搜索与输入 — combined search, search history and the remote keyboard.
  List<Widget> _searchInputRows(AppStore store) => [
        _Group(
          rows: [
            const _Row(
              icon: CupertinoIcons.doc_text_search,
              color: LcbColors.sysBlue,
              title: '聚合搜索',
              subtitle: '同时在所有源里搜索',
              toggle: true,
              toggleOn: true,
            ),
            const _Row(
              icon: CupertinoIcons.clock,
              color: LcbColors.sysIndigo,
              title: '搜索历史',
              subtitle: '记住输入过的关键词',
              toggle: true,
              toggleOn: true,
            ),
            _Row(
              icon: CupertinoIcons.keyboard,
              color: LcbColors.sysGreen,
              title: '遥控器键盘',
              subtitle: 'TV 模式下的输入方式',
              toggle: true,
              toggleValue: store.settings.tvKeyboard,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(tvKeyboard: v),
              ),
            ),
          ],
        ),
      ];

  /// 播放 — kernel, decode mode, speed, subtitles, danmaku and short-drama
  /// preload. All structural; the actual engine wiring lands in Phase 3.
  List<Widget> _playbackRows(AppStore store) => [
        const _GroupLabel('内核'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.play_rectangle_fill,
              color: LcbColors.sysIndigo,
              title: '播放内核',
              subtitle: 'mpv / ijk 等播放引擎',
              value: 'mpv',
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.slider_horizontal_3,
              color: LcbColors.sysOrange,
              title: '内核设置',
              subtitle: '默认内核、解码方式',
              onTap: () {},
            ),
            _Row(
              icon: Icons.memory,
              color: LcbColors.sysGreen,
              title: '解码方式',
              value: '硬件',
              onTap: () {},
            ),
          ],
        ),
        const SizedBox(height: 23),
        const _GroupLabel('播放'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.arrow_right_arrow_left,
              color: LcbColors.sysBlue,
              title: '跳过片头片尾',
              subtitle: '自动跳过片头片尾',
              toggle: true,
              toggleValue: store.settings.skipIntroOutro,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(skipIntroOutro: v),
              ),
            ),
            _Row(
              icon: CupertinoIcons.speedometer,
              color: LcbColors.sysPurple,
              title: '默认倍速',
              subtitle: '开始播放时的速度',
              value: '1.0x',
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.captions_bubble,
              color: LcbColors.sysPink,
              title: '字幕',
              subtitle: '外挂字幕、默认语言',
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.chat_bubble_2,
              color: LcbColors.sysTeal,
              title: '弹幕',
              subtitle: '弹幕源、显示开关',
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.film,
              color: LcbColors.sysGray,
              title: '短剧预载',
              subtitle: '提前加载下一集',
              toggle: true,
              toggleValue: store.settings.shortDramaPreload,
              onToggle: (v) => store.updateSettings(
                store.settings.copyWith(shortDramaPreload: v),
              ),
            ),
          ],
        ),
      ];

  /// 媒体徽章 — 4K / 杜比 / HDR specification badges and their badge pack.
  List<Widget> _badgeRows() => [
        _Group(
          rows: [
            const _Row(
              icon: CupertinoIcons.rosette,
              color: LcbColors.sysPurple,
              title: '显示媒体徽章',
              subtitle: '4K、杜比、HDR 等规格标签',
              toggle: true,
              toggleOn: true,
            ),
            _Row(
              icon: CupertinoIcons.rectangle_stack,
              color: LcbColors.sysBlue,
              title: '徽章包',
              subtitle: '徽章的样式与图标',
              value: '内置',
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.rectangle_3_offgrid,
              color: LcbColors.sysGreen,
              title: '显示位置',
              subtitle: '海报角落还是列表行内',
              value: '左上角',
              onTap: () {},
            ),
          ],
        ),
      ];
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
    this.toggleOn = false,
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

  /// Initial switch position when [toggle] is non-null and [toggleValue] is
  /// null (uncontrolled).
  final bool toggleOn;

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
  late bool _on = widget.toggleOn;

  bool get _isOn => widget.toggleValue ?? _on;

  void _handleTap() {
    if (widget.toggle != null) {
      if (widget.onToggle != null) {
        widget.onToggle!(!_isOn);
      } else {
        setState(() => _on = !_on);
      }
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
              else
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
