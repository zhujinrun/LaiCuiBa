import 'package:flutter/material.dart';

import 'placeholder_page.dart';

class ResourcesPage extends StatelessWidget {
  const ResourcesPage({super.key});

  @override
  Widget build(BuildContext context) => const PhasePlaceholder(
        icon: Icons.video_library_outlined,
        title: '资源',
        description: '猫源、TVBox、Emby、WebDAV、AList 与网盘挂载都会汇总在这里。\n源订阅、运行状态、出片数探测将在第二阶段接入。',
        phase: 'Phase 2 · 源接入层',
      );
}

class FavoritesPage extends StatelessWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context) => const PhasePlaceholder(
        icon: Icons.favorite_border,
        title: '收藏',
        description: '收藏的影片、追更的剧集与自定义分组。\n数据层将在第二阶段落地，届时与历史共用同一套本地存储。',
        phase: 'Phase 2 · 数据层',
      );
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) => const PhasePlaceholder(
        icon: Icons.history,
        title: '历史',
        description: '观看进度、具体集数与上次播放位置。\n这里会直接复用「继续观看」的存储结构，避免两处状态不一致。',
        phase: 'Phase 2 · 数据层',
      );
}
