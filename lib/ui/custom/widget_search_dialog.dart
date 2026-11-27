import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/detail_nav.dart';
import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../services/widgets/widget_models.dart';
import 'section_data.dart';

/// 组件自带的搜索：参数表单直接来自 `WidgetMetadata.modules[].params`，
/// 不替组件发明搜索协议。空结果和报错都原样显示，不塞假片单。
class WidgetSearchDialog extends StatefulWidget {
  const WidgetSearchDialog({
    super.key,
    required this.section,
    required this.widget,
    required this.module,
  });

  final PageSection section;
  final WidgetInfo widget;
  final WidgetModule module;

  @override
  State<WidgetSearchDialog> createState() => _WidgetSearchDialogState();
}

class _WidgetSearchDialogState extends State<WidgetSearchDialog> {
  final _controllers = <String, TextEditingController>{};
  final _values = <String, dynamic>{};
  bool _busy = false;
  SectionData? _answer;

  @override
  void initState() {
    super.initState();
    for (final param in widget.module.params) {
      final name = '${param['name'] ?? ''}';
      if (name.isEmpty) continue;
      final initial = param['defaultValue'] ?? param['value'] ?? '';
      _values[name] = initial;
      _controllers[name] = TextEditingController(text: '$initial');
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _field(Map<String, dynamic> param) {
    final name = '${param['name'] ?? ''}';
    final type = '${param['type'] ?? 'string'}';
    final label = '${param['label'] ?? param['title'] ?? name}';
    if (type == 'boolean') {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontSize: 13)),
        value: _values[name] == true,
        onChanged: (value) => setState(() => _values[name] = value),
      );
    }
    if (type == 'enum' || type == 'enumeration') {
      final options = (param['enumOptions'] ?? param['enumValues'] ?? [])
          as List<dynamic>;
      return DropdownButtonFormField<String>(
        initialValue: '${_values[name] ?? ''}',
        isDense: true,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: [
          for (final option in options)
            DropdownMenuItem<String>(
              value: '${option is Map ? option['value'] : option}',
              child: Text('${option is Map ? option['title'] ?? option['value'] : option}'),
            ),
        ],
        onChanged: (value) => setState(() => _values[name] = value),
      );
    }
    return TextField(
      controller: _controllers[name],
      keyboardType: type == 'number' ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: (value) => setState(() => _values[name] = value),
    );
  }

  Future<void> _search() async {
    final store = StoreScope.of(context);
    setState(() => _busy = true);
    final answer = await SectionDataLoader.load(
      store,
      widget.section.copyWith(params: Map<String, dynamic>.from(_values)),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _answer = answer;
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = widget.module.params.where((param) {
      final type = '${param['type'] ?? ''}';
      return type == 'string' ||
          type == 'number' ||
          type == 'enum' ||
          type == 'enumeration' ||
          type == 'boolean' ||
          type == 'language';
    }).toList();
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: 560,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 18, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${widget.widget.displayName} · ${widget.module.title}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: LcbColors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(CupertinoIcons.xmark, size: 15),
                    splashRadius: 16,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (visible.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '这个数据源没有可填写的搜索参数',
                    style: TextStyle(fontSize: 13, color: LcbColors.textSecondary),
                  ),
                ),
              for (final param in visible) ...[
                _field(param),
                const SizedBox(height: 10),
              ],
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _busy ? null : _search,
                  child: Text(_busy ? '搜索中' : '搜索'),
                ),
              ),
              if (_answer != null) ...[
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 8),
                if (_answer!.failed)
                  Text(
                    _answer!.error ?? '',
                    style: const TextStyle(fontSize: 13, color: LcbColors.sysRed),
                  )
                else if (_answer!.items.isEmpty)
                  const Text(
                    '没有找到相关内容',
                    style: TextStyle(fontSize: 13, color: LcbColors.textSecondary),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _answer!.items.length,
                      itemBuilder: (_, index) {
                        final item = _answer!.items[index];
                        return ListTile(
                          dense: true,
                          title: Text(item.title, style: const TextStyle(fontSize: 13.5)),
                          subtitle: item.subtitle == null
                              ? null
                              : Text(
                                  item.subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11.5),
                                ),
                          onTap: () {
                            Navigator.of(context).pop();
                            LcbDetailScope.openOf(context, item);
                          },
                        );
                      },
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
