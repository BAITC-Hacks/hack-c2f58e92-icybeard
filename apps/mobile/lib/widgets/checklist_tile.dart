import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import 'format.dart';
import 'status_chip.dart';

/// Пункт чек-листа обследований: название, «до даты», статус по датам. Никакой интерпретации результатов.
class ChecklistTile extends StatelessWidget {
  const ChecklistTile(this.item, {super.key});

  final ChecklistItem item;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final (tone, label) = switch (item.status) {
      RouteCodes.expired => (StatusTone.danger, s.checklistExpired),
      RouteCodes.expiring => (StatusTone.warn, s.checklistExpiring),
      _ => (StatusTone.ok, s.checklistValid),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.title, style: theme.textTheme.bodyMedium),
                Text('${s.checklistValidUntil(dateShort(item.validUntil))} · ${item.validityLabel}', style: theme.textTheme.bodySmall),
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
