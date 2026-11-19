import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../services/demo_data.dart';
import 'pages/common_pages.dart';
import 'pages/home_page.dart';
import 'pages/settings_page.dart';
import 'page_header.dart';
import 'widgets/shell_header.dart';

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  LcbPage _page = LcbPage.home;
  final _header = LcbPageHeader('首页');

  static const _titles = {
    LcbPage.home: '首页',
    LcbPage.resources: '资源',
    LcbPage.favorites: '收藏',
    LcbPage.history: '历史',
    LcbPage.settings: '设置',
  };

  @override
  void dispose() {
    _header.dispose();
    super.dispose();
  }

  void _select(LcbPage page) {
    setState(() => _page = page);
    _header.reset(_titles[page]!);
  }

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
      body: LcbPageHeaderScope(
        controller: _header,
        child: Column(
          children: [
            ShellHeader(content: _HeaderContent(page: _page)),
            Expanded(
              child: Row(
                children: [
                  _Sidebar(current: _page, onSelect: _select),
                  Expanded(child: _body()),
                ],
              ),
            ),
          ],
        ),
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
        border: Border(right: BorderSide(color: LcbColors.topBarBorder)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        children: [
          for (final (gi, group) in navGroups.indexed) ...[
            // Caption box is 18 high with the 11px copy centred, 8 of air below
            // it, and 18 above the next group. The first caption starts flush
            // with the header, so only later groups get the top gap.
            Padding(
              padding: EdgeInsets.fromLTRB(12, gi == 0 ? 0 : 18, 12, 8),
              child: SizedBox(
                height: 18,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    group.$1,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: LcbColors.sidebarLabel,
                      height: 1,
                    ),
                  ),
                ),
              ),
            ),
            for (final (ii, item) in group.$2.indexed)
              Padding(
                padding: EdgeInsets.only(
                  bottom: ii == group.$2.length - 1 ? 0 : 3,
                ),
                child: _NavItem(
                  icon: item.$1,
                  text: item.$2,
                  selected: item.$3 == current,
                  onTap: () => onSelect(item.$3),
                ),
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
    final fg = selected ? LcbColors.primaryDim : LcbColors.text;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 20, color: fg),
              const SizedBox(width: 10),
              Text(
                widget.text,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderContent extends StatelessWidget {
  const _HeaderContent({required this.page});

  final LcbPage page;

  @override
  Widget build(BuildContext context) {
    final header = LcbPageHeaderScope.of(context);
    final onBack = header.onBack;

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 8, 0),
      child: Row(
        children: [
          if (onBack != null) ...[
            _BackButton(onTap: onBack),
            const SizedBox(width: 6),
          ],
          // The original's 18px caption sits 2px below the optical centre of
          // the 60px strip; YaHei UI centres it higher, so nudge it down.
          Transform.translate(
            offset: const Offset(0, 2),
            child: Text(
              header.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: LcbColors.text,
              ),
            ),
          ),
          // Source chips belong to the home feed only; other pages have their
          // own contextual controls in the original.
          if (page == LcbPage.home) ...[
            const SizedBox(width: 17),
            const _SourceChip(
              icon: Icons.view_agenda,
              iconSize: 12,
              label: '豆儿猫源',
            ),
            const SizedBox(width: 8),
            const _SourceChip(
                icon: Icons.layers_outlined, iconSize: 20, label: '「直」荐片'),
            const SizedBox(width: 8),
            _IconGhost(icon: Icons.grid_view, onTap: () {}),
          ],
          const Expanded(child: HeaderDragGap()),
          const _SearchBox(),
        ],
      ),
    );
  }
}

class _BackButton extends StatefulWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  State<_BackButton> createState() => _BackButtonState();
}

class _BackButtonState extends State<_BackButton> {
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
          child: const Icon(
            Icons.arrow_back,
            size: 18,
            color: LcbColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _SourceChip extends StatefulWidget {
  const _SourceChip({
    required this.icon,
    required this.label,
    this.iconSize = 16,
  });

  final IconData icon;
  final String label;
  final double iconSize;

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
        height: 32,
        padding: const EdgeInsets.only(left: 10, right: 8),
        decoration: BoxDecoration(
          color: _hover ? const Color(0xFFE8E8EC) : LcbColors.searchFill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(widget.icon, size: widget.iconSize, color: LcbColors.text),
            const SizedBox(width: 8),
            Text(
              widget.label,
              style: const TextStyle(fontSize: 12.5, color: LcbColors.text),
            ),
            const SizedBox(width: 4),
            const Icon(
              Icons.keyboard_arrow_down,
              size: 14,
              color: LcbColors.textSecondary,
            ),
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
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _hover ? const Color(0xFFE8E8EC) : LcbColors.searchFill,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(widget.icon, size: 16, color: LcbColors.text),
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
        width: 232,
        height: 32,
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(
          color: _hover ? const Color(0xFFE8E8EC) : LcbColors.searchFill,
          borderRadius: BorderRadius.circular(9),
        ),
        child: const Row(
          children: [
            Icon(Icons.search, size: 16, color: LcbColors.textSecondary),
            SizedBox(width: 8),
            Text(
              '搜索...',
              style: TextStyle(fontSize: 12.5, color: LcbColors.textSecondary),
            ),
            Spacer(),
            _KeyCap('Ctrl'),
            SizedBox(width: 6),
            _KeyCap('K'),
          ],
        ),
      ),
    );
  }
}

/// The little `Ctrl` / `K` keycaps inside the search field.
class _KeyCap extends StatelessWidget {
  const _KeyCap(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFFDEDEE1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          height: 1,
          color: LcbColors.textSecondary,
        ),
      ),
    );
  }
}
