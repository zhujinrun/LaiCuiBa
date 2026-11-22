import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/skip_rule.dart';

/// 播放页弹出的「本剧片头片尾」面板。
///
/// 为什么放在播放页而不是只放设置页：片头长短是**一部剧一部剧**的事，而设置页
/// 里没有"当前在看的这部剧"这个上下文。真正能判断"这部动画片头 90 秒、那部国产
/// 剧 15 秒"的时刻，就是正在看的时候。
///
/// 语义分三层，面板上都要能看出来：
///
/// * 全局值（设置页那一组）——没单独设过的作品都用它；
/// * 本剧覆盖（[own]）——只存用户显式点过的那一半；
/// * 实际生效（[effective]）——上面两者逐字段合并的结果。
///
/// 每行六个预设，选中的那枚按**实际生效**的值高亮，所以"跟随全局"时也能一眼
/// 看到现在到底跳多少秒。
class SkipPanel extends StatelessWidget {
  const SkipPanel({
    super.key,
    required this.global,
    required this.own,
    required this.effective,
    required this.enabled,
    required this.onPicked,
  });

  /// 设置页那一组全局值，用来说明"跟随全局"跟的是什么。
  final SkipRule global;

  /// 这部作品自己设的覆盖。空表示全跟随全局。
  ///
  /// 字段名叫 `own` 而不是 `override`：后者是 Dart 的注解关键字，叫这个名字
  /// 会让同一个类里的 `@override` 解析不到。
  final SkipOverride own;

  /// 合并之后真正在执行的值。
  final SkipRule effective;

  /// 「跳过片头片尾」总开关。关掉时面板只读，点任何东西都不会真跳，
  /// 所以直接说明原因，而不是让用户点了没反应。
  final bool enabled;

  final ValueChanged<SkipOverride> onPicked;

  /// 预设秒数，0 表示"这部没有片头/片尾"。
  static const presets = <int>[0, 30, 60, 90, 120, 180];

  @override
  Widget build(BuildContext context) {
    return Container(
      // 332 = 两行各六个预设 + 组名，量出来的最窄宽度。再窄一点「180」就会被
      // 挤出边框，宁可宽一点也不要让最后一个预设看不见。
      width: 332,
      decoration: BoxDecoration(
        color: const Color(0xF21C1C1E),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x1FFFFFFF)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Text(
              '本剧片头片尾',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Text(
              _statusLine(),
              style: TextStyle(
                fontSize: 11.5,
                height: 1.35,
                color: enabled
                    ? const Color(0xFF9A9AA2)
                    : const Color(0xFFE0A0A0),
              ),
            ),
          ),
          _ChipRow(
            label: '片头',
            value: effective.intro.inSeconds,
            onTap: enabled
                ? (s) => onPicked(own.withIntro(s * 1000))
                : null,
          ),
          _ChipRow(
            label: '片尾',
            value: effective.outro.inSeconds,
            onTap: enabled
                ? (s) => onPicked(own.withOutro(s * 1000))
                : null,
          ),
          if (own.isNotEmpty)
            InkWell(
              onTap: enabled ? () => onPicked(SkipOverride.none) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.settings_backup_restore,
                      size: 14,
                      color: enabled
                          ? const Color(0xFF9A9AA2)
                          : const Color(0xFF6A6A70),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '清除本剧设置',
                      style: TextStyle(
                        fontSize: 12,
                        color: enabled
                            ? const Color(0xFF9A9AA2)
                            : const Color(0xFF6A6A70),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const SizedBox(height: 10),
        ],
      ),
    );
  }

  String _statusLine() {
    if (!enabled) return '「跳过片头片尾」已关闭，先到设置里打开';
    final g = _pair(global.intro.inSeconds, global.outro.inSeconds);
    if (own.isEmpty) return '跟随全局：$g';
    final mine = _pair(effective.intro.inSeconds, effective.outro.inSeconds);
    return '本剧单独设置：$mine · 全局 $g';
  }

  String _pair(int intro, int outro) {
    final i = intro <= 0 ? '不跳' : '$intro 秒';
    final o = outro <= 0 ? '不判' : '$outro 秒';
    return '片头 $i / 片尾 $o';
  }
}

/// 一行：左边组名，右边六个预设。
class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.label, required this.value, this.onTap});

  final String label;
  final int value;
  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 6),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFB8B8BE),
              ),
            ),
          ),
          const SizedBox(width: 4),
          for (final s in SkipPanel.presets)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _Chip(
                label: s == 0 ? '关' : '$s',
                selected: value == s,
                onTap: onTap == null ? null : () => onTap!(s),
              ),
            ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, this.onTap});

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dim = onTap == null;
    return MouseRegion(
      cursor: dim ? SystemMouseCursors.basic : SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 26,
          constraints: const BoxConstraints(minWidth: 28),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? const Color(0x337B68EE) : const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? LcbColors.primary : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? LcbColors.primary
                  : (dim ? const Color(0xFF6A6A70) : Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}
