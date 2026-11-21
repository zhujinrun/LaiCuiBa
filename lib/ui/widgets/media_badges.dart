import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../../services/badge_rule.dart';

/// 把一个 [MediaItem] 识别出的规格徽章，按用户的 [AppSettings] 取舍后渲染。
///
/// 「识别」在 `services/badge_rule.dart`（纯逻辑），「要不要显示、带不带文字、
/// 摆哪个角」在这里根据设置过滤。识别不到（中文片名没规格后缀）就什么都不
/// 画，符合「界面只显示真实数据」。
class MediaBadgeRow extends StatelessWidget {
  const MediaBadgeRow({
    super.key,
    required this.item,
    required this.settings,
    this.onTap,
  });

  final MediaItem item;
  final AppSettings settings;
  final VoidCallback? onTap;

  /// 识别 + 按设置过滤，供海报角落与详情页共用同一份取舍。
  static List<MediaBadge> badgesFor(MediaItem item, AppSettings settings) {
    if (!settings.mediaBadgesEnabled) return const [];
    final found = BadgeRule.badgesOf(
      item.title,
      remarks: item.latest,
      tag: item.tag,
    );
    if (found.isEmpty) return const [];
    // badgeSpecs 缺省视为开；显式 false 才关掉这一类。
    return found
        .where((b) => settings.badgeSpecs[b.slug] != false)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final badges = badgesFor(item, settings);
    if (badges.isEmpty) return const SizedBox.shrink();

    return Align(
      alignment: _alignmentFor(settings.badgeSpot),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final b in badges) _BadgeChip(badge: b, withText: settings.badgeText),
          ],
        ),
      ),
    );
  }

  static Alignment _alignmentFor(String spot) {
    switch (spot) {
      case 'rightTop':
        return Alignment.topRight;
      case 'leftBottom':
        return Alignment.bottomLeft;
      case 'rightBottom':
        return Alignment.bottomRight;
      case 'leftTop':
      default:
        return Alignment.topLeft;
    }
  }
}

/// 一枚规格徽章：小圆角胶囊，带一个主色底 + 白字（或纯图标短标）。
///
/// 原版是 SVG 徽章；这里用文字胶囊复刻同一观感——带文字时显示中文名
/// （如「杜比视界」），不带时显示短标（如「DV」「4K」）。
class _BadgeChip extends StatelessWidget {
  const _BadgeChip({required this.badge, required this.withText});

  final MediaBadge badge;
  final bool withText;

  Color get _color {
    switch (badge.group) {
      case BadgeGroup.quality:
        return const Color(0xFFE8A33D);
      case BadgeGroup.hdr:
        return const Color(0xFF8E5CF7);
      case BadgeGroup.audio:
        return const Color(0xFF3478F6);
      case BadgeGroup.source:
        return const Color(0xFF8E8E93);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = withText ? badge.label : badge.short;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          height: 1.1,
        ),
      ),
    );
  }
}
