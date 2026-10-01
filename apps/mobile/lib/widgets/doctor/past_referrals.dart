import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../collapsible_section.dart';
import '../format.dart';
import '../org_name.dart';
import '../status_chip.dart';

/// «Прошлые направления» пациента (веб `RouteHistory`): свёрнутая секция с числом направлений; строка — «дата ·
/// профиль», больница коротким именем (полное — по нажатию), исход чипом («Госпитализация» ok / «Отказ» danger) и
/// «ждал N дн.». Чип и срок — под текстом, чтобы длинные казахские подписи не теснили имя больницы.
class PastReferralsSection extends StatelessWidget {
  const PastReferralsSection({super.key, required this.history});

  final List<RouteHistoryItem> history;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return CollapsibleSection(
      title: s.pastReferrals,
      summary: '${history.length}',
      padded: false,
      child: Column(
        children: [
          for (final (i, item) in history.indexed)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              decoration: BoxDecoration(border: i == 0 ? null : Border(top: BorderSide(color: colors.borderSoft))),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${routeDate(item.registeredAt)} · ${item.profileName}', style: theme.textTheme.row.merge(AppType.numeric), maxLines: 2, overflow: TextOverflow.ellipsis),
                  OrgName(item.moName),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      item.outcome == RouteCodes.refused
                          ? StatusChip(s.outcomeRefused, tone: StatusTone.danger)
                          : StatusChip(s.outcomeHospitalized, tone: StatusTone.ok),
                      Text(s.waitedDays(item.waitDays), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
