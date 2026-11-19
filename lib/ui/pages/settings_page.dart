import 'package:flutter/material.dart';

import '../../core/app_info.dart';
import '../../core/theme.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          LcbMetrics.pagePadding,
          4,
          LcbMetrics.pagePadding,
          48,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 780),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('设置', style: serifStyle(22)),
              const SizedBox(height: 22),
              const _Group(
                title: '播放',
                tiles: [
                  _Tile(Icons.memory_outlined, '播放内核', 'mpv / 内置解码，硬件加速与缓存策略'),
                  _Tile(Icons.subtitles_outlined, '字幕', '字幕站点、样式、字号与描边'),
                  _Tile(Icons.forum_outlined, '弹幕', '弹幕源、透明度、速度与屏蔽词'),
                  _Tile(Icons.skip_next_outlined, '跳过片头片尾', '按剧集自动记录并跳过'),
                ],
              ),
              const _Group(
                title: '外观',
                tiles: [
                  _Tile(Icons.wallpaper_outlined, '背景与主题', '首页背景、取色与透明度'),
                  _Tile(Icons.text_fields, '字体', '界面字体与标题衬线字体'),
                  _Tile(Icons.grid_view_outlined, '首页布局', '分区顺序、每行数量与卡片比例'),
                ],
              ),
              const _Group(
                title: '源与刮削',
                tiles: [
                  _Tile(Icons.cloud_download_outlined, '源订阅', '猫源、TVBox 配置与更新策略'),
                  _Tile(Icons.image_outlined, '海报与刮削', 'TMDB / Bangumi / 豆瓣信息源'),
                  _Tile(Icons.emoji_events_outlined, '评分与徽章', '评分来源与徽章样式'),
                ],
              ),
              const _Group(
                title: '数据',
                tiles: [
                  _Tile(Icons.backup_outlined, '备份与同步', 'WebDAV 备份、配置与历史同步'),
                  _Tile(Icons.download_outlined, '下载', '下载目录、并发数与外部下载器'),
                ],
              ),
              const _Group(
                title: '网络',
                tiles: [
                  _Tile(Icons.vpn_lock_outlined, '代理', 'HTTP / SOCKS 代理与分流域名'),
                  _Tile(Icons.wifi_tethering, '本地服务', '局域网投送与网页控制端'),
                ],
              ),
              const _Group(
                title: '关于',
                tiles: [
                  _Tile(Icons.info_outline, '版本', '${LcbAppInfo.name} ${LcbAppInfo.version} · Flutter'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.tiles});

  final String title;
  final List<_Tile> tiles;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: LcbColors.textTertiary,
                letterSpacing: 0.6,
              ),
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: LcbColors.page,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEDEDF0)),
            ),
            child: Column(
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0)
                    const Divider(height: 1, thickness: 1, color: Color(0xFFEDEDF0), indent: 50),
                  tiles[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatefulWidget {
  const _Tile(this.icon, this.title, this.subtitle);

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  State<_Tile> createState() => _TileState();
}

class _TileState extends State<_Tile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: _hover ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(widget.icon, size: 18, color: LcbColors.textSecondary),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: LcbColors.text),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: LcbColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: LcbColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
