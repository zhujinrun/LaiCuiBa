import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/player/subtitle_file.dart';
import '../../services/subtitle/sites.dart';

/// 播放页「字幕网站」搜索结果。只列用户自己配过的站点；没有配置时明说，
/// 不塞假字幕。点结果下载完直接交给播放页挂到这一集。
class SubtitleSearchDialog extends StatefulWidget {
  const SubtitleSearchDialog({super.key, required this.sites});

  final List<SubtitleSite> sites;

  @override
  State<SubtitleSearchDialog> createState() => _SubtitleSearchDialogState();
}

class _SubtitleSearchDialogState extends State<SubtitleSearchDialog> {
  final _query = TextEditingController();
  late String _siteId = widget.sites.isNotEmpty ? widget.sites.first.id : '';
  bool _busy = false;
  String? _message;
  List<SubtitleHit> _hits = const [];

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    if (widget.sites.isEmpty) {
      setState(() => _message = '没有可用的字幕网站，点这里设置');
      return;
    }
    SubtitleSite? site;
    for (final candidate in widget.sites) {
      if (candidate.id == _siteId) site = candidate;
    }
    site ??= widget.sites.first;
    setState(() {
      _busy = true;
      _message = null;
      _hits = const [];
    });
    try {
      final hits = await SubtitleSiteService.search(site, _query.text.trim());
      if (!mounted) return;
      setState(() {
        _busy = false;
        _hits = hits;
        _message = hits.isEmpty ? '没有找到字幕' : null;
      });
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error.message;
      });
    }
  }

  Future<void> _download(SubtitleHit hit) async {
    setState(() => _busy = true);
    try {
      final file = await SubtitleSiteService.download(hit);
      if (!mounted) return;
      Navigator.of(context).pop(
        SubtitleFile(path: file.path, label: hit.title),
      );
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 540,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '字幕网站',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: LcbColors.text,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(CupertinoIcons.xmark, size: 15),
                    splashRadius: 16,
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.only(bottom: 10),
                child: Text(
                  '字幕来自公开的字幕网站，仅供个人学习使用。下载后记在这一集上，下次播放自动挂上。',
                  style: TextStyle(fontSize: 11.5, color: LcbColors.textSecondary),
                ),
              ),
              if (widget.sites.isEmpty)
                const Text(
                  '没有可用的字幕网站，点这里设置',
                  style: TextStyle(fontSize: 13, color: LcbColors.textSecondary),
                )
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: _siteId,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: '字幕网站',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final site in widget.sites)
                      DropdownMenuItem(value: site.id, child: Text(site.name)),
                  ],
                  onChanged: (value) => setState(() => _siteId = value ?? ''),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _query,
                  decoration: const InputDecoration(
                    labelText: '片名',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _search(),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _busy ? null : _search,
                    child: Text(_busy ? '请稍候…' : '搜索'),
                  ),
                ),
              ],
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _message!,
                    style: const TextStyle(fontSize: 12.5, color: LcbColors.sysRed),
                  ),
                ),
              if (_hits.isNotEmpty)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 300),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _hits.length,
                    itemBuilder: (_, index) {
                      final hit = _hits[index];
                      return ListTile(
                        dense: true,
                        enabled: !_busy,
                        title: Text(hit.title, style: const TextStyle(fontSize: 13)),
                        subtitle: hit.language.isEmpty
                            ? null
                            : Text(
                                hit.language,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                        trailing: const Icon(Icons.download, size: 15),
                        onTap: () => _download(hit),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
