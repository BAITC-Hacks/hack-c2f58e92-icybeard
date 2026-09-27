import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'origin_tag.dart';

/// Ряд плиток одной высоты: подпись в одной плитке переносится на вторую строку — остальные вытягиваются за ней.
class KpiRow extends StatelessWidget {
  const KpiRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(child: children[i]),
            ],
          ],
        ),
      );
}

/// Плитка показателя на soft-фоне radius 12: значение 24/500 табличными цифрами, подпись 12 ink-2 до двух строк.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.value, required this.label, this.unit, this.origin});

  final String value;
  final String label;
  final String? unit;
  final Origin? origin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: colors.neutralSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(child: Text(value, style: theme.textTheme.headlineSmall?.merge(AppType.numeric), overflow: TextOverflow.ellipsis)),
              if (unit != null) ...[const SizedBox(width: AppSpacing.xs), Text(unit!, style: theme.textTheme.bodySmall)],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(label, style: theme.textTheme.labelSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
          if (origin != null) ...[const SizedBox(height: AppSpacing.sm), OriginTag(origin!)],
        ],
      ),
    );
  }
}
