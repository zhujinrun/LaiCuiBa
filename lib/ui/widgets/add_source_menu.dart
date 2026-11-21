import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';
import '../../services/emby_client.dart';
import '../../services/source_import.dart';
import 'source_dialogs.dart';

/// The nine entries of the original's 添加资源 sheet, in its three groups.
enum AddSourceAction {
  emby,
  jellyfin,
  tvboxUrl,
  liveUrl,
  pasteText,
  importFiles,
  importLive,
  importFolder,
  importZip,
}

/// Opens 添加资源 and runs whatever the user picked.
///
/// Group and wording mirror the original 1.0.6 sheet. Four of the nine entries
/// finish entirely on this machine (imports); the rest either record what the
/// user typed for a later networked step or say plainly that the step needs one.
Future<void> showAddSourceMenu(BuildContext context) async {
  final action = await showDialog<AddSourceAction>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => const _AddSourceMenu(),
  );
  if (action == null || !context.mounted) return;
  _run(context, action);
}

/// Dispatches without awaiting: every branch is fire-and-forget from here, so
/// the context is used exactly once and there is no async gap to guard.
void _run(BuildContext context, AddSourceAction action) {
  switch (action) {
    case AddSourceAction.pasteText:
      unawaited(showAddSourceDialog(context));
    case AddSourceAction.emby:
    case AddSourceAction.jellyfin:
      unawaited(
        _showServerForm(
          context,
          type: action == AddSourceAction.emby ? 'emby' : 'jellyfin',
          title: action == AddSourceAction.emby
              ? 'Emby 服务器'
              : '飞牛影视 / Jellyfin',
          hint: action == AddSourceAction.emby
              ? 'http://192.168.1.10:8096'
              : 'http://192.168.1.10:5666',
        ),
      );
    case AddSourceAction.tvboxUrl:
      unawaited(
        _showUrlForm(
          context,
          type: 'tvbox',
          title: 'TVBox 影视源',
          nameHint: '名称（如：某某接口）',
          urlHint: '配置地址，例如 https://example.com/config.json',
          note: '地址会先存下来。拉取配置需要联网，本版暂不发起请求。',
        ),
      );
    case AddSourceAction.liveUrl:
      unawaited(
        _showUrlForm(
          context,
          type: 'live',
          title: '直播频道',
          nameHint: '名称（如：自家 IPTV）',
          urlHint: 'M3U / TXT 直播列表地址',
          note: '地址会先存下来。解析频道需要联网。',
        ),
      );
    case AddSourceAction.importFiles:
      unawaited(_importFiles(context));
    case AddSourceAction.importLive:
      unawaited(_importLiveFiles(context));
    case AddSourceAction.importFolder:
      unawaited(_importFolder(context));
    case AddSourceAction.importZip:
      unawaited(_importZip(context));
  }
}

// ---------------------------------------------------------------------------
// Imports
// ---------------------------------------------------------------------------

Future<void> _importFiles(BuildContext context) async {
  const group = XTypeGroup(
    label: '源文件',
    extensions: importableExtensions,
  );
  final files = await openFiles(acceptedTypeGroups: [group]);
  if (files.isEmpty || !context.mounted) return;
  final outcome = await importPaths(files.map((file) => file.path));
  if (!context.mounted) return;
  await _finishImport(context, outcome);
}

Future<void> _importLiveFiles(BuildContext context) async {
  const group = XTypeGroup(label: '直播列表', extensions: ['m3u', 'm3u8', 'txt']);
  final files = await openFiles(acceptedTypeGroups: [group]);
  if (files.isEmpty || !context.mounted) return;
  final outcome = await importPaths(files.map((file) => file.path));
  if (!context.mounted) return;
  await _finishImport(context, outcome);
}

Future<void> _importFolder(BuildContext context) async {
  final dir = await getDirectoryPath(confirmButtonText: '导入这个文件夹');
  if (dir == null || !context.mounted) return;
  final outcome = await importDirectory(dir);
  if (!context.mounted) return;
  await _finishImport(context, outcome);
}

Future<void> _importZip(BuildContext context) async {
  const group = XTypeGroup(label: 'ZIP 本地包', extensions: ['zip']);
  final file = await openFile(acceptedTypeGroups: [group]);
  if (file == null || !context.mounted) return;
  final outcome = await importZip(file.path);
  if (!context.mounted) return;
  await _finishImport(context, outcome);
}

/// Stores every source an import produced and reports what happened.
Future<void> _finishImport(BuildContext context, ImportOutcome outcome) async {
  final store = StoreScope.of(context);
  for (final source in outcome.sources) {
    await store.addSource(source);
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(outcome.summary),
      duration: Duration(seconds: outcome.skipped.isEmpty ? 3 : 5),
    ),
  );
}

// ---------------------------------------------------------------------------
// Forms
// ---------------------------------------------------------------------------

const _sheetWidth = 520.0;

Widget _sheet({required Widget child}) => Dialog(
  backgroundColor: Colors.white,
  insetPadding: EdgeInsets.zero,
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
  child: SizedBox(
    width: _sheetWidth,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 18),
      child: child,
    ),
  ),
);

class _TitleRow extends StatelessWidget {
  const _TitleRow(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            height: 1.0,
            color: LcbColors.text,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          behavior: HitTestBehavior.opaque,
          child: const Padding(
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

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    this.icon,
    this.obscure = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final bool obscure;

  /// The primary button's enabled state is derived from the fields, so editing
  /// one has to rebuild the sheet.
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
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
      behavior: HitTestBehavior.opaque,
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

const _noteStyle = TextStyle(
  fontSize: 11.5,
  height: 1.5,
  color: LcbColors.textTertiary,
);

/// A name + address form. Used by TVBox 地址 and 直播频道, where all this build
/// can honestly do is keep what the user typed.
Future<void> _showUrlForm(
  BuildContext context, {
  required String type,
  required String title,
  required String nameHint,
  required String urlHint,
  required String note,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => _UrlForm(
      type: type,
      title: title,
      nameHint: nameHint,
      urlHint: urlHint,
      note: note,
    ),
  );
}

class _UrlForm extends StatefulWidget {
  const _UrlForm({
    required this.type,
    required this.title,
    required this.nameHint,
    required this.urlHint,
    required this.note,
  });

  final String type;
  final String title;
  final String nameHint;
  final String urlHint;
  final String note;

  @override
  State<_UrlForm> createState() => _UrlFormState();
}

class _UrlFormState extends State<_UrlForm> {
  final _name = TextEditingController();
  final _url = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  bool get _ready => _url.text.trim().isNotEmpty;

  Future<void> _save() async {
    final store = StoreScope.of(context);
    final url = _url.text.trim();
    final name = _name.text.trim();
    await store.addSource(
      SourceInfo(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: widget.type,
        name: name.isEmpty ? widget.title : name,
        url: url,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已添加「${name.isEmpty ? widget.title : name}」，地址已保存'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleRow(widget.title),
          const SizedBox(height: 16),
          _Field(
            controller: _name,
            hint: widget.nameHint,
            icon: CupertinoIcons.at,
          ),
          const SizedBox(height: 12),
          _Field(
            controller: _url,
            hint: widget.urlHint,
            icon: CupertinoIcons.link,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          Text(widget.note, style: _noteStyle),
          const SizedBox(height: 12),
          _PrimaryButton(label: '添加', onTap: _ready ? _save : null),
        ],
      ),
    );
  }
}

/// Emby / Jellyfin: address + account. The password is deliberately not stored
/// -- there is no token to store it against until the mount layer exists.
Future<void> _showServerForm(
  BuildContext context, {
  required String type,
  required String title,
  required String hint,
}) {
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => _ServerForm(type: type, title: title, hint: hint),
  );
}

class _ServerForm extends StatefulWidget {
  const _ServerForm({
    required this.type,
    required this.title,
    required this.hint,
  });

  final String type;
  final String title;
  final String hint;

  @override
  State<_ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends State<_ServerForm> {
  final _name = TextEditingController();
  final _url = TextEditingController();
  final _user = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  bool get _ready => _url.text.trim().isNotEmpty && !_busy;
  bool _busy = false;
  String? _error;

  /// Logs in for real, then keeps the token and drops the password.
  ///
  /// Saving a mount without a successful login would produce a source that
  /// looks configured and answers nothing -- the exact "added but broken" state
  /// the card's 未连接 label exists to avoid. So the dialog stays open on
  /// failure and says why, and only a server that returned a token is saved.
  Future<void> _save() async {
    final store = StoreScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final url = _url.text.trim();
    final name = _name.text.trim();
    final user = _user.text.trim();
    final password = _password.text;

    if (user.isEmpty || password.isEmpty) {
      setState(() => _error = '要填账号和密码才能登录，密码不会被保存');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    EmbyAuth auth;
    try {
      auth = await EmbyClient.authenticate(
        baseUrl: url,
        username: user,
        password: password,
      );
    } on EmbyException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
      return;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '登录失败：$e';
      });
      return;
    }

    await store.addSource(
      SourceInfo(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        type: widget.type,
        name: name.isEmpty ? widget.title : name,
        url: url,
        username: user,
        token: auth.token,
        tokenUserId: auth.userId,
      ),
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('已登录「${name.isEmpty ? widget.title : name}」并添加'),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _sheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleRow(widget.title),
          const SizedBox(height: 16),
          _Field(
            controller: _name,
            hint: '名称（可不填）',
            icon: CupertinoIcons.at,
          ),
          const SizedBox(height: 12),
          _Field(
            controller: _url,
            hint: '服务器地址，例如 ${widget.hint}',
            icon: CupertinoIcons.link,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _Field(
            controller: _user,
            hint: '用户名（可不填）',
            icon: CupertinoIcons.person,
          ),
          const SizedBox(height: 12),
          _Field(
            controller: _password,
            hint: '密码（不保存）',
            icon: CupertinoIcons.lock,
            obscure: true,
          ),
          const SizedBox(height: 10),
          const Text(
            '点「添加」时会真正登录一次；成功后只保存登录令牌，密码不写入本机。',
            style: _noteStyle,
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              key: const ValueKey('server-form-error'),
              style: _noteStyle.copyWith(color: LcbColors.sysRed),
            ),
          ],
          const SizedBox(height: 12),
          _PrimaryButton(
            label: _busy ? '正在登录…' : '添加',
            onTap: _ready ? _save : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// The sheet
// ---------------------------------------------------------------------------

class _AddSourceMenu extends StatelessWidget {
  const _AddSourceMenu();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: const SizedBox(
        width: 520,
        child: Padding(
          padding: EdgeInsets.fromLTRB(22, 18, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TitleRow('添加资源'),
              SizedBox(height: 14),
              _GroupLabel('媒体服务器'),
              _Group(
                rows: [
                  _MenuRow(
                    icon: CupertinoIcons.tv,
                    color: LcbColors.sysGreen,
                    title: 'Emby 服务器',
                    subtitle: '用账号登录自己的或朋友分享的 Emby',
                    action: AddSourceAction.emby,
                  ),
                  _MenuRow(
                    icon: CupertinoIcons.play_circle_fill,
                    color: LcbColors.sysBlue,
                    title: '飞牛影视 / Jellyfin',
                    subtitle: '飞牛 NAS（fnOS）影视与 Jellyfin 服务器',
                    action: AddSourceAction.jellyfin,
                  ),
                ],
              ),
              SizedBox(height: 16),
              _GroupLabel('影视源'),
              _Group(
                rows: [
                  _MenuRow(
                    icon: CupertinoIcons.square_stack_3d_up,
                    color: LcbColors.sysBlueDark,
                    title: 'TVBox 影视源',
                    subtitle: '填配置地址；电脑版能用其中的采集站与 Python 站点',
                    action: AddSourceAction.tvboxUrl,
                  ),
                  _MenuRow(
                    icon: CupertinoIcons.waveform_path_ecg,
                    color: LcbColors.sysOrange,
                    title: '直播频道',
                    subtitle: 'M3U / TXT 直播列表地址',
                    action: AddSourceAction.liveUrl,
                  ),
                  _MenuRow(
                    icon: CupertinoIcons.doc_text,
                    color: LcbColors.sysSky,
                    title: '粘贴站点 / 配置文本',
                    subtitle: '一两个站点（含 js 源），或整份配置 JSON',
                    action: AddSourceAction.pasteText,
                  ),
                ],
              ),
              SizedBox(height: 16),
              _GroupLabel('从本地导入'),
              _Group(
                rows: [
                  _MenuRow(
                    icon: CupertinoIcons.arrow_down_doc_fill,
                    color: LcbColors.sysIndigo,
                    title: '导入文件',
                    subtitle: 'py / php / TVBox 配置 / 直播列表，可多选',
                    action: AddSourceAction.importFiles,
                  ),
                  _MenuRow(
                    icon: CupertinoIcons.waveform_path_ecg,
                    color: LcbColors.sysOrange,
                    title: '导入直播列表文件',
                    subtitle: '本地 M3U / TXT 直播源，可多选',
                    action: AddSourceAction.importLive,
                  ),
                  _MenuRow(
                    icon: CupertinoIcons.folder_fill,
                    color: LcbColors.sysPurple,
                    title: '导入文件夹里的源',
                    subtitle: '递归导入文件夹中的 py / php / json / txt / m3u',
                    action: AddSourceAction.importFolder,
                  ),
                  _MenuRow(
                    icon: CupertinoIcons.archivebox_fill,
                    color: LcbColors.sysGray,
                    title: '从 ZIP 本地包导入',
                    subtitle: 'TVBox 本地包、drpy-node（DS）本地包、PHP 源包',
                    action: AddSourceAction.importZip,
                  ),
                ],
              ),
            ],
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
      padding: const EdgeInsets.only(left: 6, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: LcbColors.textTertiary),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: LcbColors.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(children: rows),
    );
  }
}

class _MenuRow extends StatefulWidget {
  const _MenuRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.action,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final AddSourceAction action;

  @override
  State<_MenuRow> createState() => _MenuRowState();
}

class _MenuRowState extends State<_MenuRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(widget.action),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _hover ? Colors.white : null,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: widget.color,
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: LcbColors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: LcbColors.settingsQuiet,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                CupertinoIcons.chevron_forward,
                size: 15,
                color: LcbColors.chevron,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
