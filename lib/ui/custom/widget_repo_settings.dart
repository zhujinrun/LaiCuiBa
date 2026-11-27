import 'package:file_selector/file_selector.dart' show XTypeGroup, openFile;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../services/widgets/widget_center.dart';
import '../../services/widgets/widget_models.dart';

/// 设置里的「组件仓库」区，对应原版 `widgets_settings_page.dart` 的仓库管理。
class WidgetRepoSettings extends StatefulWidget {
  const WidgetRepoSettings({super.key});

  @override
  State<WidgetRepoSettings> createState() => _WidgetRepoSettingsState();
}

class _WidgetRepoSettingsState extends State<WidgetRepoSettings> {
  late List<WidgetRepo> _repos = WidgetCenter.repos(StoreScope.of(context));
  late List<WidgetInfo> _widgets = WidgetCenter.widgets(StoreScope.of(context));
  String? _notice;
  String _query = '';

  void _reload() {
    final store = StoreScope.of(context);
    setState(() {
      _repos = WidgetCenter.repos(store);
      _widgets = WidgetCenter.widgets(store);
    });
  }

  Future<void> _importAddress() async {
    final address = await showDialog<String>(
      context: context,
      builder: (_) => const _AddressDialog(),
    );
    if (address == null || address.trim().isEmpty) return;
    await _import(address);
  }

  Future<void> _importFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: '组件脚本',
          extensions: ['js', 'json'],
        ),
      ],
    );
    if (file == null) return;
    await _import(file.path);
  }

  Future<void> _import(String address) async {
    final store = StoreScope.of(context);
    String message;
    try {
      final repo = await WidgetCenter.importAddress(store, address);
      message = repo == null ? '没有导入任何组件' : '已导入 ${repo.displayName}';
    } on FormatException catch (error) {
      message = error.message;
    } on Object catch (error) {
      message = '$error';
    }
    if (!mounted) return;
    setState(() => _notice = message);
    _reload();
  }

  Future<void> _deleteRepo(WidgetRepo repo) async {
    final store = StoreScope.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除组件仓库'),
        content: const Text('组件仓库或数据源已被删除；用到这些组件的页面区域会显示加载失败。'),
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
    await WidgetCenter.deleteRepo(store, repo.id);
    _reload();
  }

  Future<void> _group(WidgetInfo widget) async {
    final store = StoreScope.of(context);
    final group = await showDialog<String>(
      context: context,
      builder: (_) => _GroupDialog(current: widget.group),
    );
    if (group == null) return;
    await WidgetCenter.setWidgetGroup(store, widget.id, group);
    _reload();
  }

  Future<void> _proxy() async {
    final store = StoreScope.of(context);
    final value = await showDialog<WidgetProxy>(
      context: context,
      builder: (_) => _ProxyDialog(current: WidgetCenter.proxy(store)),
    );
    if (value == null) return;
    await WidgetCenter.setProxy(store, value);
    if (!mounted) return;
    setState(() => _notice = value.enabled ? '组件网络已改走代理' : '组件代理已关闭');
  }

  Future<void> _logs() async {
    final lines = WidgetCenter.recentLogs(StoreScope.of(context));
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('组件日志'),
        content: SizedBox(
          width: 520,
          height: 320,
          child: lines.isEmpty
              ? const Text(
                  '本次启动后组件还没有输出日志',
                  style: TextStyle(fontSize: 13, color: LcbColors.textSecondary),
                )
              : SingleChildScrollView(
                  child: Text(
                    lines.join('\n'),
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  ),
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('组件仓库与自定义首页页面'),
        _card([
          _row(
            icon: CupertinoIcons.link,
            title: '导入组件仓库',
            subtitle: '填写组件脚本地址，或列出多个地址的 JSON 仓库索引',
            onTap: _importAddress,
          ),
          _row(
            icon: CupertinoIcons.folder,
            title: '选择组件脚本',
            subtitle: '从本地文件导入 .js / .json',
            onTap: _importFile,
          ),
          _row(
            icon: Icons.network_check,
            title: '组件代理',
            subtitle: '只代理组件脚本发出的请求。配置只保存在本机',
            onTap: _proxy,
          ),
          _row(
            icon: CupertinoIcons.doc_text,
            title: '组件日志',
            subtitle: '本次启动后组件输出的信息',
            onTap: _logs,
          ),
          _row(
            icon: CupertinoIcons.arrow_counterclockwise,
            title: '恢复内置组件库',
            subtitle: '随应用更新；删除后可在组件页恢复',
            onTap: () => setState(() => _notice = '没有能恢复的组件库'),
          ),
        ]),
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: Text(
              _notice!,
              key: const ValueKey('widget-repo-message'),
              style: const TextStyle(fontSize: 12.5, color: LcbColors.sysBlue),
            ),
          ),
        const SizedBox(height: 16),
        if (_repos.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Text(
              '还没有导入组件仓库',
              style: TextStyle(fontSize: 13, color: LcbColors.textSecondary),
            ),
          ),
        for (final repo in _repos) ...[
          _card([
            _row(
              icon: CupertinoIcons.square_stack_3d_down_right,
              title: repo.displayName,
              subtitle: '${repo.widgetIds.length} 个组件 · ${repo.address}',
              value: '删除',
              onTap: () => _deleteRepo(repo),
            ),
          ]),
          const SizedBox(height: 12),
        ],
        if (_widgets.isNotEmpty) ...[
          const _Heading('组件'),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
            child: SizedBox(
              height: 34,
              child: TextField(
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: const InputDecoration(
                  hintText: '搜索组件名称',
                  prefixIcon: Icon(Icons.search, size: 16),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          ),
        ],
        for (final widget in _widgets.where(
          (widget) =>
              _query.isEmpty ||
              widget.displayName.contains(_query) ||
              widget.group.contains(_query),
        )) ...[
          _card([
            _row(
              icon: Icons.extension,
              title: widget.displayName,
              subtitle: widget.group.isEmpty
                  ? '${widget.modules.length} 个数据源 · 未分组'
                  : '${widget.modules.length} 个数据源 · ${widget.group}',
              value: '分组',
              iconUrl: widget.icon,
              onTap: () => _group(widget),
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
    String? iconUrl,
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
            iconUrl != null && iconUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.network(
                      iconUrl,
                      width: 24,
                      height: 24,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.extension,
                        size: 18,
                        color: LcbColors.sysPurple,
                      ),
                    ),
                  )
                : Icon(icon, size: 18, color: LcbColors.sysPurple),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: LcbColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (value != null)
              Text(
                value,
                style: const TextStyle(fontSize: 12, color: LcbColors.sysBlue),
              ),
          ],
        ),
      ),
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: LcbColors.settingsQuiet),
    ),
  );
}

class _AddressDialog extends StatefulWidget {
  const _AddressDialog();

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('导入组件仓库'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '组件地址',
              hintText: 'https://…/widget.js 或仓库索引.json',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '只安装来源可信的组件：组件可以访问网络。',
            style: TextStyle(fontSize: 12, color: LcbColors.textSecondary),
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
        onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
        child: const Text('导入'),
      ),
    ],
  );
}

class _GroupDialog extends StatefulWidget {
  const _GroupDialog({required this.current});

  final String current;

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('组件分组'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      decoration: const InputDecoration(
        labelText: '分组名称',
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

class _ProxyDialog extends StatefulWidget {
  const _ProxyDialog({required this.current});

  final WidgetProxy current;

  @override
  State<_ProxyDialog> createState() => _ProxyDialogState();
}

class _ProxyDialogState extends State<_ProxyDialog> {
  late final _url = TextEditingController(text: widget.current.url);
  late final _user = TextEditingController(text: widget.current.username);
  late final _pass = TextEditingController(text: widget.current.password);

  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('组件代理'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _url,
            decoration: const InputDecoration(
              labelText: '代理地址',
              hintText: 'http://127.0.0.1:7890',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _user,
            decoration: const InputDecoration(
              labelText: '账号（可不填）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '密码（可不填）',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            '只代理这个组件脚本发出的请求；支持 HTTP、HTTPS 和账号密码。配置只保存在本机，不随备份或同步传输。\n电脑版的组件代理暂不支持 SOCKS5，请改用 HTTP 代理。',
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
        onPressed: () => Navigator.of(context).pop(
          WidgetProxy(
            url: _url.text.trim(),
            username: _user.text.trim(),
            password: _pass.text,
          ),
        ),
        child: const Text('保存'),
      ),
    ],
  );
}
