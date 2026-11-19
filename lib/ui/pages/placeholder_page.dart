import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Honest placeholder for modules that belong to a later phase. Keeps the shell
/// navigable while the source layer is not wired up yet.
class PhasePlaceholder extends StatelessWidget {
  const PhasePlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.phase,
  });

  final IconData icon;
  final String title;
  final String description;
  final String phase;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: LcbColors.primaryContainer,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 28, color: LcbColors.onPrimaryContainer),
            ),
            const SizedBox(height: 18),
            Text(title, style: serifStyle(20)),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12.5, height: 1.6, color: LcbColors.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: LcbColors.page,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                phase,
                style: const TextStyle(fontSize: 11, color: LcbColors.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
