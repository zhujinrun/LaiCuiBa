import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../services/subtitle/sites.dart';

/// 设置里的「字幕网站」子页。原版没有内置可用站点，只有配置入口和一句说明；
/// 没配时在播放页也说「没有可用的字幕网站，点这里设置」，而不是塞假结果。
class SubtitleSitesSettings extends StatefulWidget {
  const SubtitleSitesSettings({super.key});

  @override
  State<SubtitleSitesSettings> createState() => _SubtitleSitesSettingsState();
}

class _SubtitleSitesSettingsState extends State<SubtitleSitesSettings> {
  late List<SubtitleSite> _sites = _read();

  List<SubtitleSite> _read() => [
    for (final raw in StoreScope.of(context).settings.subtitleSites)
      if ((raw['id'] as String?)?.isNotEmpty ?? false)
        SubtitleSite.fromJson(raw),
  ];

  void _reload() => setState(() => _sites = _read());

  Future<void> _write(List<SubtitleSite> sites) async {
    final store = StoreScope.of(context);
    await store.updateSettings(
      store.settings.copyWith(
        subtitleSites: [for (final site in sites) site.toJson()],
      ),
    );
    _reload();
  }

  Future<void> _add() async {
    final added = await showDialog<SubtitleSite>(
      context: context,
      builder: (_) => const _SubtitleSiteDialog(),
    );
    if (added == null) return;
    await _write([..._sites, added]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card([
          _row(
            icon: CupertinoIcons.add,
            title: '添加字幕网站',
            subtitle: '填一个搜索地址，用 {query} 代表片名',
            onTap: _add,
          ),
        ]),
        const Padding(
          padding: EdgeInsets.fromLTRB(10, 12, 10, 6),
          child: Text(
            '字幕来自公开的字幕网站，仅供个人学习使用。下载后记在这一集上，下次播放自动挂上。',
            style: TextStyle(fontSize: 12.5, color: LcbColors.textSecondary),
          ),
        ),
        const SizedBox(height: 12),
        if (_sites.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 20),
            child: Text(
              '没有可用的字幕网站，点上面添加',
              style: TextStyle(fontSize: 13, color: LcbColors.textSecondary),
            ),
          ),
        for (final site in _sites) ...[
          _card([
            _row(
              icon: CupertinoIcons.globe,
              title: site.name,
              subtitle: site.urlTemplate,
              value: '删除',
              onTap: () => _write(
                _sites.where((candidate) => candidate.id != site.id).toList(),
              ),
            ),
          ]),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _card(List<Widget> rows) => DecoratedBox(
    decoration: BoxDecoration(
      color: LcbColors.card,
      borderRadius: BorderRadius.circular(LcbMetrics.settingsCardRadius),
    ),
    child: Column(children: rows),
  );

  Widget _row({
    required IconData icon,
    required String title,
    required String subtitle,
    String? value,
    required VoidCallback onTap,
  }) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: SizedBox(
      height: LcbMetrics.settingsRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(icon, size: 18, color: LcbColors.sysTeal),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: LcbColors.text,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: LcbColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (value != null)
              Text(
                value,
                style: const TextStyle(fontSize: 12, color: LcbColors.sysRed),
              ),
          ],
        ),
      ),
    ),
  );
}

class _SubtitleSiteDialog extends StatefulWidget {
  const _SubtitleSiteDialog();

  @override
  State<_SubtitleSiteDialog> createState() => _SubtitleSiteDialogState();
}

class _SubtitleSiteDialogState extends State<_SubtitleSiteDialog> {
  final _name = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('添加字幕网站'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(
              labelText: '名称',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: '搜索地址',
              hintText: 'https://example.com/api?q={query}',
              isDense: true,
              border: OutlineInputBorder(),
            ),
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
          final url = _url.text.trim();
          final name = _name.text.trim();
          if (name.isEmpty || !url.startsWith('http')) return;
          Navigator.of(context).pop(
            SubtitleSite(
              id: 'site-${DateTime.now().microsecondsSinceEpoch}',
              name: name,
              urlTemplate: url,
            ),
          );
        },
        child: const Text('保存'),
      ),
    ],
  );
}
