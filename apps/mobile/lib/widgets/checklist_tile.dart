import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'format.dart';
import 'status_chip.dart';

/// Пункт чек-листа обследований строкой списка: название 15, «до даты · срок» 13 ink-2, чип статуса по датам.
/// Никакой интерпретации результатов.
class ChecklistTile extends StatelessWidget {
  const ChecklistTile(this.item, {super.key, this.last = false});

  final ChecklistItem item;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final (tone, label) = switch (item.status) {
      RouteCodes.expired => (StatusTone.danger, s.checklistExpired),
      RouteCodes.expiring => (StatusTone.warn, s.checklistExpiring),
      _ => (StatusTone.ok, s.checklistValid),
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: last ? null : BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: theme.textTheme.row),
                Text(
                  '${s.checklistValidUntil(dateShort(item.validUntil))} · ${item.validityLabel}',
                  style: theme.textTheme.rowDetail.copyWith(color: colors.muted).merge(AppType.numeric),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          StatusChip(label, tone: tone),
        ],
      ),
    );
  }
}
