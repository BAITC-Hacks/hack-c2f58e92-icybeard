import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../app_card.dart';
import '../format.dart';
import '../status_chip.dart';
import 'citizen_route_rules.dart';

/// «Что дальше» (RouteCitizenView.vue, блок C) — строки «что | значение»: дата госпитализации (назначенная или
/// ожидаемая) с больницей; «Обновить анализы: N истекли» со ссылкой «Посмотреть» ([onSeeTests] раскрывает
/// «Анализы» и прокручивает к ним); «Действуют: N»; следующий этап с нормой срока (или текущий этап); «Перевод не
/// состоялся» с исходом последней попытки, пока пациент ждёт в своей больнице (F7, второе лицо — Q4); открытая
/// просьба с чипом «Ждёт ответа врача».
class RouteNextCard extends StatelessWidget {
  const RouteNextCard({super.key, required this.route, required this.onSeeTests});

  final PatientRoute route;
  final VoidCallback onSeeTests;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final org = route.organization;
    final planned = route.dates.plannedAt;
    final expired = route.checklist.where((c) => c.status == RouteCodes.expired).toList();
    final valid = route.checklist.where((c) => c.status != RouteCodes.expired).toList();
    final next = route.nextStage;
    final current = route.timeline.where((stage) => stage.status == RouteCodes.current).firstOrNull;
    final attempt = routeIsWaiting(route) ? route.progress?.lastAttempt : null;
    final request = route.openRequest;
    final rows = <({String title, String? sub, Widget? trailing})>[
      (
        title: planned != null ? s.myDatePlanned : s.myDateExpected,
        sub: '${shortOrgName(org.moName)} · ${org.moCode}',
        trailing: RowValue(routeDate(planned ?? route.dates.expectedAt), strong: true),
      ),
      if (expired.isNotEmpty)
        (title: s.myUpdateTests(expired.length), sub: expired.map((c) => c.title).join(' · '), trailing: TextButton(onPressed: onSeeTests, child: Text(s.view))),
      if (valid.isNotEmpty)
        (
          title: s.myValidTests(valid.length),
          sub: '${valid.first.title} · ${s.checklistValidUntil(routeDate(valid.first.validUntil))}',
          trailing: StatusChip(s.checklistValid, tone: StatusTone.ok),
        ),
      if (next != null)
        (title: next.title, sub: next.norm == null || next.norm!.isEmpty ? null : '${s.myNormLabel}: ${next.norm}', trailing: null)
      else if (current != null)
        (title: current.title, sub: null, trailing: null),
      if (attempt != null)
        (
          title: s.routeAttemptTitle,
          sub: [
            s.routeAttemptText(attempt.outcome, RouteVoice.citizen, name: shortOrgName(attempt.toMoName)),
            if (attempt.reason?.trim().isNotEmpty ?? false) '«${attempt.reason!.trim()}»',
          ].join(' — '),
          trailing: null,
        ),
      if (request != null)
        (
          title: s.routeJournalTitle(RouteCodes.journalRequest, RouteVoice.citizen, name: shortOrgName(request.toMoName)),
          sub: null,
          trailing: StatusChip(s.awaitingDoctor, tone: StatusTone.accent),
        ),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.myWhatNext),
          for (final (i, row) in rows.indexed) ListRow(title: row.title, subtitle: row.sub, trailing: row.trailing, last: i == rows.length - 1),
        ],
      ),
    );
  }
}
