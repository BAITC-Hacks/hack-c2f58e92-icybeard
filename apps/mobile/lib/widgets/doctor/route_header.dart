import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../format.dart';
import '../org_name.dart';
import '../route/priority_badge.dart';
import '../status_chip.dart';
import 'fact_grid.dart';
import 'worklist_logic.dart';

/// Шапка маршрута пациента для врача (веб `route-card`): «ПАЦИЕНТ», номер и бейдж приоритета 0…10, кнопка «Записать
/// приём» (скрайб этого пациента — если экран её передал), чипы всех флагов риска с тонами списка, строка статуса
/// маршрута («Маршрут завершён · Выписан»), больница коротким именем (полное — по нажатию) с профилем и кодом и факты
/// «В листе ожидания с · Ждёт · Приоритет · Данные на».
class PatientRouteHeader extends StatelessWidget {
  const PatientRouteHeader({super.key, required this.route, this.onRecordVisit});

  final PatientRoute route;

  /// Открыть скрайб для этого пациента; null — кнопки нет (нет `scribe.use` или врач не сторона маршрута).
  final VoidCallback? onRecordVisit;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final doctor = route.doctor;
    final progress = route.progress;
    final org = route.organization;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardLabel(s.patientRouteKicker),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(child: Text(route.patientRef, style: theme.textTheme.headlineSmall?.merge(AppType.numeric))),
              if (doctor != null) ...[const SizedBox(width: AppSpacing.sm), PriorityBadge(doctor.priority)],
            ],
          ),
          if (onRecordVisit != null) ...[
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              style: AppButtons.small(context),
              onPressed: onRecordVisit,
              icon: const Icon(Icons.mic_none, size: 18),
              label: Text(s.patientRouteRecordVisit),
            ),
          ],
          if (doctor != null && doctor.riskFlags.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [for (final flag in doctor.riskFlags) StatusChip(s.worklistFlag(flag), tone: worklistFlagTone(flag))],
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(s.routeStatusLine(progress.status, closedReason: progress.closedReason), style: theme.textTheme.row),
          ],
          const SizedBox(height: AppSpacing.md),
          OrgName(org.moName, style: theme.textTheme.titleSmall, maxLines: 2),
          Text([org.profileName, org.moCode].where((part) => part.isNotEmpty).join(' · '), style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          FactGrid(facts: [
            RouteFact(s.patientRouteSince, routeDate(route.dates.registeredAt)),
            RouteFact(s.patientRouteWaiting, s.patientRouteDays(route.daysWaiting)),
            if (doctor != null) RouteFact(s.worklistColumnPriority, s.priorityOutOfTen(priorityScore(doctor.priority))),
            RouteFact(s.patientRouteAsOfFact, routeDate(route.asOf)),
          ]),
        ],
      ),
    );
  }
}
