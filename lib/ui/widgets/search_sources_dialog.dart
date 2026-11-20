import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/search_state.dart';
import '../../core/store_scope.dart';
import '../../core/theme.dart';
import '../../models/models.dart';

/// 搜索哪些资源 -- the source picker behind the header's grid glyph and the
/// circular button in the bottom-right corner.
///
/// Measured at 1920x1040: a 558x561 sheet whose centre lands on the content
/// column (1072) rather than the window (960), so the left inset reserves the
/// sidebar. Title ink 25 from the top edge, a 30px pill, then 58px source rows
/// with the one-line hint right under the last one.
Future<void> showSearchSourcesSheet(BuildContext context) {
  final search = LcbSearchScope.of(context);
  final store = StoreScope.of(context);
  return showDialog<void>(
    context: context,
    barrierColor: const Color(0x78000000),
    builder: (_) => _SearchSourcesDialog(search: search, sources: store.sources),
  );
}

class _SearchSourcesDialog extends StatelessWidget {
  const _SearchSourcesDialog({required this.search, required this.sources});

  final LcbSearch search;
  final List<SourceInfo> sources;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      // Centring happens inside the inset box, so reserving the sidebar on the
      // left pushes the sheet over the content column.
      insetPadding: const EdgeInsets.only(
        left: LcbMetrics.sidebarWidth,
        top: 24,
        bottom: 24,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: SizedBox(
        width: 558,
        height: 561,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: _TitleBar(onClose: () => Navigator.of(context).pop()),
              ),
              const SizedBox(height: 17),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    _ClearAllPill(onTap: search.clearSources),
                    const SizedBox(height: 20),
                    for (final source in sources) ...[
                      _SourceRow(
                        source: source,
                        selected: search.isSourceSelected(source.id),
                        onTap: () => search.toggleSource(
                          source.id,
                          sources.map((s) => s.id),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 2),
                    const Text(
                      '点资源加入或取消，可同时选多个，也可以整组全选；直播、网络挂载只能单独搜索。',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: LcbColors.settingsQuiet,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          '搜索哪些资源',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.0,
            color: LcbColors.text,
          ),
        ),
        const SizedBox(width: 10),
        // Placeholder for the original's per-source filter field.
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: LcbColors.card,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            CupertinoIcons.search,
            size: 14,
            color: LcbColors.settingsQuiet,
          ),
        ),
        const Spacer(),
        _CircleButton(icon: CupertinoIcons.xmark, onTap: onClose),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: LcbColors.card,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 12, color: LcbColors.text),
        ),
      ),
    );
  }
}

class _ClearAllPill extends StatelessWidget {
  const _ClearAllPill({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: LcbColors.card,
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.minus_circle,
                size: 15,
                color: LcbColors.primaryDim,
              ),
              SizedBox(width: 7),
              Text(
                '取消选择“全部”',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.0,
                  color: LcbColors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  final SourceInfo source;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: LcbColors.card,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  source.type == 'tvbox'
                      ? CupertinoIcons.film
                      : CupertinoIcons.tray_2,
                  size: 16,
                  color: LcbColors.text,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        height: 1.0,
                        color: LcbColors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      source.type == 'tvbox' ? 'TVBox 影视源' : source.type,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.0,
                        color: LcbColors.settingsQuiet,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (selected)
                const Icon(
                  CupertinoIcons.checkmark_alt,
                  size: 18,
                  color: LcbColors.primaryDim,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
