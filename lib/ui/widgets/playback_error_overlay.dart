import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/player/playback_failure.dart';

/// 画面中间那块「这一集打不开」。
///
/// 播放页原来只把失败 `debugPrint` 掉：视频区一片黑，和正在加载没有区别。这里
/// 把三件事摆出来——发生了什么（一句人话）、播放器原话（grey，给能看懂的人）、
/// 以及能做的动作（重试 / 切换线路）。线路失效时下一集也播不了，别摆那个按钮。
class PlaybackErrorOverlay extends StatelessWidget {
  const PlaybackErrorOverlay({
    super.key,
    required this.raw,
    required this.onRetry,
    this.onSwitchLine,
    this.retrying = false,
  });

  /// mpv / 系统给的原始信息，原样留给能看懂的人。
  final String raw;

  final VoidCallback onRetry;

  /// 有别的线路才显示，没有就不摆一个按不动的按钮。
  final VoidCallback? onSwitchLine;

  /// 重试请求已经发出、还没结果：按钮改成「正在重试…」并禁掉重复点击。
  final bool retrying;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xB3000000),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 30,
                color: Color(0xCCFFFFFF),
              ),
              const SizedBox(height: 14),
              const Text(
                '这一集打不开',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                playbackFailureHint(raw),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: Color(0xE6FFFFFF),
                ),
              ),
              if (raw.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  raw.trim(),
                  key: const ValueKey('playback-error-raw'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: Color(0x8CFFFFFF),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _Action(
                    label: retrying ? '正在重试…' : '重试',
                    filled: true,
                    onTap: retrying ? null : onRetry,
                  ),
                  if (onSwitchLine != null) ...[
                    const SizedBox(width: 10),
                    _Action(
                      label: '切换线路',
                      filled: false,
                      onTap: onSwitchLine,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.label, required this.filled, this.onTap});

  final String label;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled
              ? (enabled ? LcbColors.primaryDim : const Color(0x66FFFFFF))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: filled
              ? null
              : Border.all(color: const Color(0x59FFFFFF), width: 1),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
