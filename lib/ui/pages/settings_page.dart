import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme.dart';
import '../page_header.dart';

/// Settings root + the 外观 sub-page.
///
/// Structure, wording and metrics come from the original 1.0.6 build: two
/// groups on the root (通用 / 账号与服务) and a single card on 外观. Rows are
/// 70px tall with a 36px tinted icon disc, a 17px title and a 13.5px subtitle.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _title = '设置';

  /// Null on the root list, [subAppearance] on the 外观 sub-page.
  static const subAppearance = '外观';

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
          _sub == subAppearance ? 35 : 8,
          LcbMetrics.settingsPaddingRight,
          40,
        ),
        children: _sub == subAppearance ? _appearanceRows() : _rootRows(),
      ),
    );
  }

  List<Widget> _rootRows() => [
        const _GroupLabel('通用'),
        _Group(
          rows: [
            _Row(
              icon: CupertinoIcons.paintbrush_fill,
              color: LcbColors.sysIndigo,
              title: '外观',
              subtitle: '深浅色、强调色、液态玻璃、状态栏',
              value: '自动',
              onTap: () => _open(subAppearance),
            ),
            _Row(
              icon: CupertinoIcons.house_fill,
              color: LcbColors.sysOrange,
              title: '首页与导航',
              subtitle: '导航栏、首页入口、轮播海报',
              onTap: () {},
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
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.play_rectangle_fill,
              color: LcbColors.sysPink,
              title: '播放',
              subtitle: '手势、弹幕、倍速、字幕、短片预载',
              onTap: () {},
            ),
            _Row(
              icon: CupertinoIcons.rosette,
              color: LcbColors.sysPurple,
              title: '媒体徽章',
              subtitle: '4K、杜比、HDR 等规格徽章的开关、显示位置和徽章包',
              value: '内置',
              onTap: () {},
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
              onTap: () {},
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

  List<Widget> _appearanceRows() => [
        _Group(
          rows: [
            _Row(
              icon: Icons.contrast,
              color: LcbColors.sysIndigo,
              title: '外观模式',
              value: '自动',
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
              value: '简体中文',
              onTap: () {},
            ),
            _Row(
              icon: Icons.text_fields,
              color: LcbColors.sysGray,
              title: '字体与字号',
              onTap: () {},
            ),
            const _Row(
              icon: Icons.palette_outlined,
              color: LcbColors.sysPurple,
              title: '自适应颜色',
              subtitle: '首页配色跟随顶部推荐封面的主色',
              toggle: false,
            ),
            const _Row(
              icon: Icons.blur_on,
              color: LcbColors.sysTeal,
              title: '液态玻璃',
              subtitle: '关闭后底栏与悬浮按钮使用纯色',
              toggle: false,
            ),
            _Row(
              icon: Icons.tv,
              color: LcbColors.sysBlue,
              title: '电视模式',
              subtitle: '顶部导航、遥控器方向键操作；盒子没被识别成电视时手动开启',
              value: '自动（非电视）',
              onTap: () {},
            ),
            const _Row(
              icon: Icons.auto_fix_high_outlined,
              color: LcbColors.sysPurple,
              title: '隐藏状态栏',
              subtitle: '让首页封面延伸到屏幕顶端',
              toggle: false,
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

  /// Initial switch position when [toggle] is non-null.
  final bool toggleOn;

  final VoidCallback? onTap;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool _hover = false;
  late bool _on = widget.toggleOn;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.toggle != null
            ? () => setState(() => _on = !_on)
            : widget.onTap,
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
                  child: _Switch(value: _on),
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
