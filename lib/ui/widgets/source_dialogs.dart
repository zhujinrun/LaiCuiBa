import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/config_fetcher.dart';
import '../../services/script_runtime.dart';
import '../../services/site_parser.dart';
import '../../services/source_probe.dart';
import '../../services/store.dart';
import 'source_icon_picker.dart';

/// Source management dialogs.
///
/// The original's 添加资源 sheet offers nine entry points. Eight of them need
/// either the network (fetch a config URL) or the spider runtime (import a jar),
/// so the only one that can be made real today is 粘贴站点 / 配置文本: it parses
/// a document the user already has. Deliberately wired to the real parser rather
/// than to a placeholder, because this is what proves the rest of the pipeline:
/// what is added here is what the search page fans out over.
Future<void> showAddSourceDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => const _AddSourceDialog(),
  );
}

/// The card's `⋯` menu: 设为当前资源 / 重新检测 / 编辑 / 删除, matching the
/// original's four items.
Future<void> showSourceMenu(BuildContext context, SourceInfo source) async {
  final store = StoreScope.of(context);
  final action = await showDialog<_SourceAction>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => _SourceMenuDialog(
      source: source,
      isCurrent: store.currentSourceId == source.id,
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case _SourceAction.select:
      await store.selectSource(source.id);
    case _SourceAction.recheck:
      if (!context.mounted) return;
      await _recheckSource(context, store, source);
    case _SourceAction.edit:
      if (!context.mounted) return;
      await showEditSourceDialog(context, source);
    case _SourceAction.group:
      if (!context.mounted) return;
      await showSourceGroupDialog(context, source);
    case _SourceAction.icon:
      if (!context.mounted) return;
      await showSourceIconPicker(context, source);
    case _SourceAction.delete:
      if (!context.mounted) return;
      await showDeleteSourceDialog(context, source);
  }
}

/// Checks [source] and writes the outcome back, with no UI of its own.
///
/// The four branches are the same ones a single-source 检测 walks: a mount asks
/// its server, a 猫源 or script source is *run*, and a plain config document is
/// fetched. Nothing here throws -- a dead source is a result, not an exception --
/// so both 检测 (one card) and 检测全部 (the whole list) can share it.
Future<({String line, bool ok})> probeSourceQuietly(
  AppStore store,
  SourceInfo source,
) async {
  // 直播源问的是「有多少频道」，不是「有多少站点」：它的列表里没有 site 也没有
  // 片名，交给下面任何一条分支都会得到「没有解析到站点」这种冤枉的失败。
  if (source.type == 'live') {
    if (source.url.trim().isEmpty) {
      return (line: '${source.name}：没有直播列表地址', ok: false);
    }
    if (!source.url.trimLeft().toLowerCase().startsWith('http')) {
      return (line: '${source.name}：本地列表已在导入时数过频道', ok: true);
    }
    final report = await store.probeLiveSource(source);
    final detail = report.ok
        ? '${report.showCount} 个频道，${report.latencyMs} ms'
        : report.error!;
    return (line: '${source.name}：$detail', ok: report.ok);
  }

  if (AppStore.isMountSource(source)) {
    if (store.mountClientOf(source) == null) {
      return (line: '${source.name}：还没登录，编辑它重填一次账号', ok: false);
    }
    final report = await store.probeSource(source, '');
    return (line: '${source.name}：${_probeSummary(report, mount: true)}', ok: report.ok);
  }

  final address = store.spiderAddressOf(source);
  if (address != null) {
    if (store.spider == null) {
      return (line: '${source.name}：没有可用的源运行时', ok: false);
    }
    final report = await store.probeSource(source, address);
    return (line: '${source.name}：${_probeSummary(report)}', ok: report.ok);
  }

  if (store.scriptSitesOf(source).isNotEmpty) {
    if (store.scripts == null) {
      return (line: '${source.name}：没有脚本运行时', ok: false);
    }
    final report = await store.probeSource(source, '');
    return (line: '${source.name}：${_probeSummary(report)}', ok: report.ok);
  }

  if (source.url.trim().isEmpty) {
    return (line: '${source.name}：没有配置地址', ok: false);
  }
  if (_isLocalSpider(source)) {
    return (line: '${source.name}：本地 spider 文件不能直接跑', ok: false);
  }

  final result = await fetchConfig(source.url);
  if (!result.ok) {
    await store.updateSource(source.copyWith(latencyMs: result.latencyMs));
    return (
      line: '${source.name}：${result.error ?? result.note ?? '没有拉到站点'}',
      ok: false,
    );
  }
  final home = source.homeSite.isNotEmpty
      ? source.homeSite
      : (result.sites.isEmpty ? '' : result.sites.first.key);
  await store.updateSource(
    source.copyWith(
      sites: result.sites,
      homeSite: home,
      latencyMs: result.latencyMs,
      checkedAt: DateTime.now().millisecondsSinceEpoch,
    ),
  );
  return (
    line: '${source.name}：${result.sites.length} 个站点，${result.latencyMs} ms',
    ok: true,
  );
}

/// What to say while [source] is being checked -- the wait differs enough by
/// kind (a server handshake, a worker boot, an HTTP round trip) that one
/// 「正在检测…」 would hide what is actually happening.
String _stageLine(AppStore store, SourceInfo source) {
  if (source.type == 'live') return '正在读取直播列表…';
  if (AppStore.isMountSource(source)) return '正在连接服务器并读取影片库…';
  if (store.spiderAddressOf(source) != null) return '正在启动源并读取首页…';
  if (store.scriptSitesOf(source).isNotEmpty) return '正在启动 Python 源并读取首页…';
  return '正在拉取配置…';
}

Future<void> _recheckSource(
  BuildContext context,
  AppStore store,
  SourceInfo source,
) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(
    SnackBar(
      content: Text(_stageLine(store, source)),
      duration: const Duration(minutes: 2),
    ),
  );
  final result = await probeSourceQuietly(store, source);
  if (!context.mounted) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(result.line),
      duration: const Duration(seconds: 4),
    ),
  );
}

/// 检测全部资源：check every source, write each outcome back, then sort the
/// list by the latency just measured -- the original's「测速完成，已按速度排序」.
///
/// Runs one source at a time on purpose. These checks boot runtimes and hold
/// them in memory; firing ten at once would multiply that peak for no gain the
/// user can see, and the order of results would no longer follow the list.
Future<void> checkAllSources(BuildContext context) async {
  final store = StoreScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final sources = List<SourceInfo>.from(store.sources);
  if (sources.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('还没有资源可检测')));
    return;
  }

  messenger.showSnackBar(
    SnackBar(
      content: Text('共检测 ${sources.length} 个资源…'),
      duration: const Duration(minutes: 10),
    ),
  );

  var ok = 0;
  for (final source in sources) {
    final result = await probeSourceQuietly(store, source);
    if (result.ok) ok++;
    if (!context.mounted) return;
  }

  // Latency 0 means the check never got a number (dead, or nothing to time).
  // Those sink below the ones that answered, keeping their own relative order.
  final ordered = List<SourceInfo>.from(store.sources);
  ordered.sort((a, b) {
    final la = a.latencyMs > 0 ? a.latencyMs : 1 << 30;
    final lb = b.latencyMs > 0 ? b.latencyMs : 1 << 30;
    return la.compareTo(lb);
  });
  await store.reorderSources([for (final source in ordered) source.id]);
  if (!context.mounted) return;

  final failed = sources.length - ok;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        '测速完成，已按速度排序（$ok 个正常${failed > 0 ? '，$failed 个异常' : ''}）',
      ),
      duration: const Duration(seconds: 4),
    ),
  );
}

/// One line for the toast: what the check measured, or why it failed.
///
/// [mount] changes the wording of [ProbeReport.showCount]: for a 猫源 it is how
/// many categories the home screen declared, for a mount it is how many series
/// the library holds. Same field, different sentence.
String _probeSummary(ProbeReport report, {bool mount = false}) {
  if (!report.ok) {
    final reason = report.error!;
    return report.latencyMs > 0
        ? '$reason（用时 ${report.latencyMs} ms）'
        : reason;
  }
  final parts = <String>[
    if (mount && report.showCount > 0) '${report.showCount} 部剧集',
    if (!mount && report.showCount > 0) '${report.showCount} 个分类',
    mount ? '${report.movieCount} 部电影' : '首页 ${report.movieCount} 部',
    '用时 ${report.latencyMs} ms',
  ];
  final note = report.note == null ? '' : '（${report.note}）';
  return '${parts.join('，')}$note';
}

/// A 猫源 shipped as a local file: it has a path, but the cat host is pointed at
/// a subscription (a directory with `index.js`), not at one loose file.
///
/// Script sources are not in this group: a TVBox source *is* one file, so a
/// script host runs it in place (`services/script_runtime.dart`). What is left
/// here is a catvod bundle on disk, which needs a directory, not a file.
bool _isLocalSpider(SourceInfo source) {
  const kinds = {'js', 'php'};
  if (!kinds.contains(source.type)) return false;
  if (source.url.startsWith('http')) return false;
  return !isScriptApi(source.url);
}

Future<void> showEditSourceDialog(BuildContext context, SourceInfo source) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => _EditSourceDialog(source: source),
  );
}

Future<void> showDeleteSourceDialog(BuildContext context, SourceInfo source) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => _DeleteSourceDialog(source: source),
  );
}

/// 「放进分组」：给一个组名，留空就回到按类型自动分组。
Future<void> showSourceGroupDialog(BuildContext context, SourceInfo source) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => _SourceGroupDialog(source: source),
  );
}

/// Confirms deleting the ticked sources. True means go ahead; the caller does
/// the actual removal so it can clear the selection and leave 多选 in one step.
Future<bool?> showDeleteSourcesConfirm(
  BuildContext context,
  List<String> ids,
) {
  return showDialog<bool>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => _DeleteSourcesDialog(ids: ids),
  );
}

enum _SourceAction { select, recheck, edit, group, icon, delete }

// ---------------------------------------------------------------------------
// Shared chrome
// ---------------------------------------------------------------------------

const _dialogWidth = 558.0;

Widget _sheet({required Widget child, EdgeInsetsGeometry? padding}) {
  return Dialog(
    backgroundColor: Colors.white,
    insetPadding: EdgeInsets.zero,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    child: SizedBox(
      width: _dialogWidth,
      child: Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(22, 18, 16, 18),
        child: child,
      ),
    ),
  );
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({
    required this.title,
    this.circularClose = false,
    this.fontSize = 17,
    this.fontWeight = FontWeight.w700,
  });

  final String title;

  /// The card `⋯` menu has a 28px grey disc for its close button; the larger
  /// form sheets use a plain xmark. Both stay opt-in so other sheets are
  /// untouched.
  final bool circularClose;
  final double fontSize;
  final FontWeight fontWeight;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            height: 1.0,
            color: LcbColors.text,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.opaque,
          child: circularClose
              ? Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: LcbColors.searchFill,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    CupertinoIcons.xmark,
                    size: 14,
                    color: LcbColors.textSecondary,
                  ),
                )
              : const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(
                    CupertinoIcons.xmark,
                    size: 16,
                    color: LcbColors.textSecondary,
                  ),
                ),
        ),
      ],
    );
  }
}

/// The rounded grey field the original uses for every text input in a sheet.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.icon,
    this.maxLines = 1,
    this.height,
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final int maxLines;
  final double? height;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final field = TextField(
      controller: controller,
      maxLines: maxLines,
      autofocus: autofocus,
      onChanged: onChanged,
      cursorColor: LcbColors.primary,
      style: const TextStyle(fontSize: 14, height: 1.3, color: LcbColors.text),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: LcbColors.searchFill,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: LcbColors.textTertiary),
        prefixIcon: icon == null
            ? null
            : Icon(icon, size: 16, color: LcbColors.textTertiary),
        prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
      ),
    );
    if (height == null) return field;
    return SizedBox(height: height, child: field);
  }
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? LcbColors.primary : LcbColors.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: enabled ? Colors.white : LcbColors.primaryDim,
          ),
        ),
      ),
    );
  }
}

const _hintStyle = TextStyle(
  fontSize: 11.5,
  height: 1.5,
  color: LcbColors.textTertiary,
);

// ---------------------------------------------------------------------------
// 添加资源
// ---------------------------------------------------------------------------

class _AddSourceDialog extends StatefulWidget {
  const _AddSourceDialog();

  @override
  State<_AddSourceDialog> createState() => _AddSourceDialogState();
}

class _AddSourceDialogState extends State<_AddSourceDialog> {
  final _name = TextEditingController();
  final _text = TextEditingController();
  SiteParseResult? _result;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  void _preview(String value) {
    setState(() {
      _result = value.trim().isEmpty ? null : parseConfig(value);
    });
  }

  Future<void> _add() async {
    final result = _result;
    if (result == null || !result.ok || _saving) return;
    setState(() => _saving = true);
    final store = StoreScope.of(context);
    final name = _name.text.trim();
    await store.addSource(
      SourceInfo(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: 'tvbox',
        name: name.isEmpty ? '粘贴的源' : name,
        url: '',
        sites: result.sites,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final ready = result?.ok == true && result!.sites.isNotEmpty;
    return _sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TitleRow(title: '添加影视源'),
          const SizedBox(height: 16),
          _Field(controller: _name, hint: '名称（可不填）', icon: CupertinoIcons.at),
          const SizedBox(height: 12),
          _Field(
            controller: _text,
            hint: '粘贴配置内容：{"sites":[…] }、站点数组，或每行一个「名称\$地址」',
            maxLines: 8,
            height: 190,
            onChanged: _preview,
            autofocus: true,
          ),
          const SizedBox(height: 10),
          _ParsePreview(result: result),
          const SizedBox(height: 12),
          _PrimaryButton(label: '添加', onTap: ready ? _add : null),
          const SizedBox(height: 10),
          const Text(
            '配置在本地解析，不联网。解析出的站点会进入搜索与首页，'
            '可在资源页的「编辑」里逐个关掉。',
            style: _hintStyle,
          ),
        ],
      ),
    );
  }
}

class _ParsePreview extends StatelessWidget {
  const _ParsePreview({required this.result});

  final SiteParseResult? result;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    if (result == null) {
      return const Text('还没有内容', style: _hintStyle);
    }
    if (!result.ok) {
      return Row(
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_circle,
            size: 14,
            color: LcbColors.sysRed,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              result.error!,
              style: const TextStyle(fontSize: 12, color: LcbColors.sysRed),
            ),
          ),
        ],
      );
    }

    final names = result.sites.take(4).map((site) => site.name).join(' / ');
    final more = result.sites.length > 4 ? ' 等' : '';
    final silenced = result.silenced > 0
        ? '，其中 ${result.silenced} 个默认不参与搜索'
        : '';
    return Row(
      children: [
        const Icon(
          CupertinoIcons.check_mark_circled,
          size: 14,
          color: LcbColors.scoreGreen,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '解析到 ${result.count} 个站点：$names$more$silenced',
            style: const TextStyle(
              fontSize: 12,
              color: LcbColors.settingsQuiet,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 编辑资源
// ---------------------------------------------------------------------------

class _EditSourceDialog extends StatefulWidget {
  const _EditSourceDialog({required this.source});

  final SourceInfo source;

  @override
  State<_EditSourceDialog> createState() => _EditSourceDialogState();
}

class _EditSourceDialogState extends State<_EditSourceDialog> {
  late final _name = TextEditingController(text: widget.source.name);
  late final _url = TextEditingController(text: widget.source.url);
  final _siteFilter = TextEditingController();
  bool _showSites = false;
  String _siteQuery = '';

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _siteFilter.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = StoreScope.of(context);
    await store.updateSource(
      widget.source.copyWith(
        name: _name.text.trim().isEmpty
            ? widget.source.name
            : _name.text.trim(),
        url: _url.text.trim(),
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    // Read through the store so toggling a site rebuilds this sheet with the
    // new state instead of a stale copy.
    final source = store.sources.firstWhere(
      (item) => item.id == widget.source.id,
      orElse: () => widget.source,
    );
    final sites = source.sites;
    final searching = source.searchableSites.length;
    final needle = _siteQuery.trim();
    // A source can declare dozens of sites (the seeded one declares 59), so the
    // expanded list gets a filter instead of a long scroll.
    final listed = needle.isEmpty
        ? sites
        : sites.where((site) => site.name.contains(needle)).toList();
    final summary = sites.isEmpty
        ? '还没有站点'
        : searching == sites.length
        ? '站点 ${sites.length} 个'
        : '站点 ${sites.length} 个 · $searching 个参与搜索';

    return _sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TitleRow(title: '编辑资源'),
          const SizedBox(height: 16),
          _Field(controller: _name, hint: '名称', icon: CupertinoIcons.at),
          const SizedBox(height: 12),
          _Field(
            controller: _url,
            hint: '配置地址（可留空，粘贴添加的源没有地址）',
            icon: CupertinoIcons.link,
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: sites.isEmpty
                ? null
                : () => setState(() => _showSites = !_showSites),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.square_list,
                  size: 16,
                  color: LcbColors.textSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  summary,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: LcbColors.text,
                  ),
                ),
                const Spacer(),
                if (sites.isNotEmpty)
                  Icon(
                    _showSites
                        ? CupertinoIcons.chevron_up
                        : CupertinoIcons.chevron_down,
                    size: 14,
                    color: LcbColors.textTertiary,
                  ),
              ],
            ),
          ),
          if (_showSites && sites.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: LcbColors.searchFill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.search,
                    size: 14,
                    color: LcbColors.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _siteFilter,
                      onChanged: (value) => setState(() => _siteQuery = value),
                      style: const TextStyle(fontSize: 13),
                      cursorHeight: 16,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText: '搜索站点',
                        hintStyle: TextStyle(
                          fontSize: 13,
                          color: LcbColors.textTertiary,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    '${listed.length}/${sites.length}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: LcbColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              height: 232,
              decoration: BoxDecoration(
                color: LcbColors.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: listed.isEmpty
                  ? const Center(
                      child: Text(
                        '没有匹配的站点',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: LcbColors.textTertiary,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: listed.length,
                      itemBuilder: (_, index) {
                        final site = listed[index];
                        return SizedBox(
                          height: 44,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    site.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: site.enabled
                                          ? LcbColors.text
                                          : LcbColors.textTertiary,
                                    ),
                                  ),
                                ),
                                Transform.scale(
                                  scale: 0.8,
                                  child: CupertinoSwitch(
                                    value: site.enabled,
                                    onChanged: (_) =>
                                        store.toggleSite(source.id, site.key),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
            const Text('关掉的站点不会参与搜索，也不会出现在结果的站点标签里。', style: _hintStyle),
          ],
          const SizedBox(height: 14),
          _PrimaryButton(label: '保存', onTap: _save),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 卡片菜单 / 删除确认
// ---------------------------------------------------------------------------

class _SourceMenuDialog extends StatelessWidget {
  const _SourceMenuDialog({required this.source, required this.isCurrent});

  final SourceInfo source;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    return _sheet(
      padding: const EdgeInsets.fromLTRB(22, 20, 14, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TitleRow(
            title: source.name,
            circularClose: true,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
          const SizedBox(height: 14),
          // The original groups the actions in a #F6F6F8 rounded card with
          // inset dividers between rows, not as bare rows on the white sheet.
          Container(
            decoration: BoxDecoration(
              color: LcbColors.card,
              borderRadius:
                  BorderRadius.circular(LcbMetrics.settingsCardRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _MenuRow(
                  label: '设为当前资源',
                  enabled: !isCurrent,
                  onTap: () => Navigator.of(context).pop(_SourceAction.select),
                ),
                _MenuRow(
                  label: '重新检测',
                  onTap: () => Navigator.of(context).pop(_SourceAction.recheck),
                ),
                _MenuRow(
                  label: '编辑',
                  onTap: () => Navigator.of(context).pop(_SourceAction.edit),
                ),
                _MenuRow(
                  label: '更换图标',
                  onTap: () => Navigator.of(context).pop(_SourceAction.icon),
                ),
                _MenuRow(
                  label: '放进分组',
                  onTap: () => Navigator.of(context).pop(_SourceAction.group),
                ),
                _MenuRow(
                  label: '删除',
                  danger: true,
                  showDivider: false,
                  onTap: () => Navigator.of(context).pop(_SourceAction.delete),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.danger = false,
    this.showDivider = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool enabled;
  final bool danger;
  final bool showDivider;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.enabled;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MouseRegion(
          cursor: interactive ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: interactive ? (_) => setState(() => _hovered = true) : null,
          onExit: interactive ? (_) => setState(() => _hovered = false) : null,
          child: GestureDetector(
            onTap: interactive ? widget.onTap : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              // Instant, not animated: a fading row background reads as a
              // flicker when the pointer crosses the menu (see sidebar hover).
              color: interactive && _hovered
                  ? LcbColors.searchFill
                  : Colors.transparent,
              padding: const EdgeInsets.only(left: 16),
              child: SizedBox(
                height: 50,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 15,
                      color: !interactive
                          ? LcbColors.textTertiary
                          : widget.danger
                          ? LcbColors.sysRed
                          : LcbColors.text,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (widget.showDivider)
          const Padding(
            padding: EdgeInsets.only(left: 26, right: 16),
            child: SizedBox(
              height: 1,
              child: ColoredBox(color: LcbColors.cardDivider),
            ),
          ),
      ],
    );
  }
}

class _DeleteSourceDialog extends StatelessWidget {
  const _DeleteSourceDialog({required this.source});

  final SourceInfo source;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    return _sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TitleRow(title: '删除资源'),
          const SizedBox(height: 16),
          Text(
            '删除「${source.name}」后，它下面的 ${source.sites.length} 个站点'
            '会一起从搜索里消失。收藏和历史不受影响。',
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: LcbColors.settingsQuiet,
            ),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () async {
              await store.removeSource(source.id);
              if (!context.mounted) return;
              Navigator.of(context).pop();
            },
            child: Container(
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: LcbColors.sysRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '删除',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 批量删除确认：说清删几个、连带多少站点，再让人按那个红按钮。
class _DeleteSourcesDialog extends StatelessWidget {
  const _DeleteSourcesDialog({required this.ids});

  final List<String> ids;

  @override
  Widget build(BuildContext context) {
    final store = StoreScope.of(context);
    final picked = <SourceInfo>[
      for (final source in store.sources)
        if (ids.contains(source.id)) source,
    ];
    final sites = picked.fold<int>(0, (sum, s) => sum + s.sites.length);
    return _sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleRow(title: '删除 ${picked.length} 个资源'),
          const SizedBox(height: 16),
          Text(
            '删除后，这 ${picked.length} 个资源下的 $sites 个站点会一起从搜索里'
            '消失。收藏和历史不受影响。',
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: LcbColors.settingsQuiet,
            ),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(true),
            child: Container(
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: LcbColors.sysRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '删除 ${picked.length} 个',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 「放进分组」表单：一个输入框 + 已有组名的快捷选择，留空＝按类型分组。
class _SourceGroupDialog extends StatefulWidget {
  const _SourceGroupDialog({required this.source});

  final SourceInfo source;

  @override
  State<_SourceGroupDialog> createState() => _SourceGroupDialogState();
}

class _SourceGroupDialogState extends State<_SourceGroupDialog> {
  late final TextEditingController _group = TextEditingController(
    text: widget.source.groupName,
  );

  @override
  void dispose() {
    _group.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await StoreScope.of(context).setSourceGroup(
      widget.source.id,
      _group.text,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    // Groups that already exist, offered as one-tap fills so a second source
    // lands in the same group without retyping the name and splitting it.
    final existing = <String>{
      for (final source in StoreScope.of(context).sources)
        if (source.groupName.isNotEmpty) source.groupName,
    }.toList()..sort();

    return _sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TitleRow(title: '放进分组'),
          const SizedBox(height: 16),
          _Field(
            controller: _group,
            hint: '分组名称（留空就按类型自动分组）',
            icon: CupertinoIcons.folder,
            onChanged: (_) => setState(() {}),
          ),
          if (existing.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in existing)
                  GestureDetector(
                    onTap: () => setState(() => _group.text = name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: LcbColors.card,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: LcbColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            '同一个组名会把资源收到一起；留空就按资源类型自动分组。',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.5,
              color: LcbColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          _PrimaryButton(label: '保存', onTap: _save),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 分组
// ---------------------------------------------------------------------------

enum GroupAction { rename, dissolve }

/// The ⋯ on a user group's header: the two things 管理分组 can do to one group.
///
/// A type group has no ⋯ at all -- its name is derived from the source type, so
/// there is nothing to rename, and "deleting" it would only mean moving the
/// sources to another type.
Future<void> showGroupManager(
  BuildContext context, {
  required String label,
  required int count,
}) async {
  final action = await showDialog<GroupAction>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => _GroupMenu(label: label, count: count),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case GroupAction.rename:
      await _showGroupRename(context, label);
    case GroupAction.dissolve:
      await _showGroupDissolve(context, label, count);
  }
}

class _GroupMenu extends StatelessWidget {
  const _GroupMenu({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return _sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleRow(title: '分组「$label」'),
          const SizedBox(height: 6),
          Text('$count 个资源', style: _hintStyle),
          const SizedBox(height: 14),
          _MenuTile(
            icon: CupertinoIcons.pencil,
            label: '重命名分组',
            onTap: () => Navigator.of(context).pop(GroupAction.rename),
          ),
          const SizedBox(height: 8),
          _MenuTile(
            icon: CupertinoIcons.trash,
            label: '删除分组',
            danger: true,
            onTap: () => Navigator.of(context).pop(GroupAction.dissolve),
          ),
        ],
      ),
    );
  }
}

/// A flat, full-width row inside a sheet. Deliberately not a ListTile: the rest
/// of the app's sheets are hand-built, and this keeps the same 42px rhythm as
/// [_PrimaryButton].
class _MenuTile extends StatefulWidget {
  const _MenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_MenuTile> createState() => _MenuTileState();
}

class _MenuTileState extends State<_MenuTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tint = widget.danger ? LcbColors.sysRed : LcbColors.text;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hover ? LcbColors.card : LcbColors.searchFill,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 15, color: tint),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _showGroupRename(BuildContext context, String label) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => _GroupRenameDialog(label: label),
  );
}

/// Renames a group, or empties the name and thereby dissolves it -- 原版
/// 「分组名称（留空移出分组）」.
class _GroupRenameDialog extends StatefulWidget {
  const _GroupRenameDialog({required this.label});

  final String label;

  @override
  State<_GroupRenameDialog> createState() => _GroupRenameDialogState();
}

class _GroupRenameDialogState extends State<_GroupRenameDialog> {
  late final TextEditingController _group = TextEditingController(
    text: widget.label,
  );

  @override
  void dispose() {
    _group.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final store = StoreScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = _group.text.trim();
    final moved = await store.renameGroup(widget.label, name);
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          name.isEmpty
              ? '已移出分组，$moved 个资源回到按类型分组'
              : moved == 0
              ? '没有资源在这个分组里'
              : '已改名为「$name」，$moved 个资源跟过来',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final others = [
      for (final name in StoreScope.of(context).customGroups)
        if (name != widget.label) name,
    ];
    return _sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TitleRow(title: '重命名分组'),
          const SizedBox(height: 16),
          _Field(
            controller: _group,
            hint: '分组名称（留空就移出分组）',
            icon: CupertinoIcons.folder,
            autofocus: true,
            onChanged: (_) => setState(() {}),
          ),
          if (others.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final name in others)
                  GestureDetector(
                    onTap: () => setState(() => _group.text = name),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: LcbColors.card,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: LcbColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          const Text(
            '改名后组里的资源一起跟过去；写成另一个已有的组名，两组会合成一组。',
            style: _hintStyle,
          ),
          const SizedBox(height: 12),
          _PrimaryButton(label: '保存', onTap: _save),
        ],
      ),
    );
  }
}

Future<void> _showGroupDissolve(
  BuildContext context,
  String label,
  int count,
) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => _DissolveGroupDialog(label: label, count: count),
  );
  if (ok != true || !context.mounted) return;
  final store = StoreScope.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final moved = await store.renameGroup(label, '');
  if (!context.mounted) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        moved == 0 ? '这个分组已经是空的' : '已按类型重新分组，$moved 个资源移回原类型',
      ),
      duration: const Duration(seconds: 2),
    ),
  );
}

class _DissolveGroupDialog extends StatelessWidget {
  const _DissolveGroupDialog({required this.label, required this.count});

  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return _sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleRow(title: '删除分组「$label」'),
          const SizedBox(height: 16),
          Text(
            '这 $count 个资源不会删除，会回到按类型的分组。',
            style: const TextStyle(
              fontSize: 13,
              height: 1.6,
              color: LcbColors.settingsQuiet,
            ),
          ),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: () => Navigator.of(context).pop(true),
            child: Container(
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: LcbColors.sysRed,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                '删除分组',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
