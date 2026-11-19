import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/demo_data.dart';
import 'pages/common_pages.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'widgets/title_bar.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  LcbPage _page = LcbPage.home;

  static const _titles = {
    LcbPage.home: '首页',
    LcbPage.resources: '资源',
    LcbPage.favorites: '收藏',
    LcbPage.history: '历史',
    LcbPage.settings: '设置',
  };

  Widget _body() {
    switch (_page) {
      case LcbPage.home:
        return const HomePage();
      case LcbPage.resources:
        return const ResourcesPage();
      case LcbPage.favorites:
        return const FavoritesPage();
      case LcbPage.history:
        return const HistoryPage();
      case LcbPage.settings:
        return const SettingsPage();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LcbColors.surface,
      body: Column(
        children: [
          const TitleBar(),
          Expanded(
            child: Row(
              children: [
                _Sidebar(
                  current: _page,
                  onSelect: (p) => setState(() => _page = p),
                ),
                Expanded(
                  child: Column(
                    children: [
                      _TopBar(title: _titles[_page]!),
                      Expanded(child: _body()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, required this.onSelect});

  final LcbPage current;
  final ValueChanged<LcbPage> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: LcbMetrics.sidebarWidth,
      decoration: const BoxDecoration(
        color: LcbColors.page,
        border: Border(right: BorderSide(color: Color(0xFFEDEDF0))),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 16),
        children: [
          for (final (label, items) in navGroups) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 6),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: LcbColors.textTertiary,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            for (final (icon, text, page) in items)
              _NavItem(
                icon: icon,
                text: text,
                selected: page == current,
                onTap: () => onSelect(page),
              ),
          ],
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.text,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String text;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final bg = selected
        ? LcbColors.primaryContainer
        : (_hover ? LcbColors.hover : Colors.transparent);
    final fg = selected ? LcbColors.onPrimaryContainer : LcbColors.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 18,
                  color: selected ? LcbColors.primary : LcbColors.textSecondary,
                ),
                const SizedBox(width: 10),
                Text(
                  widget.text,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: LcbMetrics.topBarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: LcbMetrics.pagePadding),
        child: Row(
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: LcbColors.text,
              ),
            ),
            const SizedBox(width: 22),
            const _SourceChip(label: '豆儿猫源'),
            const SizedBox(width: 8),
            const _SourceChip(label: '[直] 荐片'),
            const SizedBox(width: 8),
            _IconGhost(icon: Icons.dashboard_customize_outlined, onTap: () {}),
            const Spacer(),
            const _SearchBox(),
          ],
        ),
      ),
    );
  }
}

class _SourceChip extends StatefulWidget {
  const _SourceChip({required this.label});

  final String label;

  @override
  State<_SourceChip> createState() => _SourceChipState();
}

class _SourceChipState extends State<_SourceChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _hover ? LcbColors.hover : LcbColors.page,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Text(
              widget.label,
              style: const TextStyle(fontSize: 12, color: LcbColors.text),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.keyboard_arrow_down, size: 16, color: LcbColors.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _IconGhost extends StatefulWidget {
  const _IconGhost({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  State<_IconGhost> createState() => _IconGhostState();
}

class _IconGhostState extends State<_IconGhost> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: _hover ? LcbColors.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(widget.icon, size: 17, color: LcbColors.textSecondary),
        ),
      ),
    );
  }
}

class _SearchBox extends StatefulWidget {
  const _SearchBox();

  @override
  State<_SearchBox> createState() => _SearchBoxState();
}

class _SearchBoxState extends State<_SearchBox> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Container(
        width: 300,
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _hover ? const Color(0xFFE8E8EC) : LcbColors.searchFill,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            const Icon(Icons.search, size: 16, color: LcbColors.textSecondary),
            const SizedBox(width: 8),
            const Text(
              '搜索...',
              style: TextStyle(fontSize: 12.5, color: LcbColors.textSecondary),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Ctrl K',
                style: TextStyle(fontSize: 10, color: LcbColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
