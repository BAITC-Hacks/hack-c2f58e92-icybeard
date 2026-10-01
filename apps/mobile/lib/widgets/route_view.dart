import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import 'citizen/citizen_route_rules.dart';
import 'citizen/route_action_zone.dart';
import 'citizen/route_faster_card.dart';
import 'citizen/route_forecast_card.dart';
import 'citizen/route_head_card.dart';
import 'citizen/route_next_card.dart';
import 'citizen/route_records.dart';
import 'collapsible_section.dart';
import 'format.dart';
import 'origin_tag.dart';
import 'route/checklist_groups.dart';
import 'route/route_journal.dart';

/// Тело «Моего пути» гражданина одной прокруткой в порядке §13.2: шапка «Ваша больница» с этапами; зона действия
/// (запрос записи приёма, затем одна карточка — состояние маршрута, ответ врача или «Вы ещё ждёте?»); «Что
/// дальше»; «Прогноз» и «Где быстрее» (кроме переведённого, госпитализированного и завершённого маршрута, Q18);
/// свёрнутые «Анализы» (их раскрывает «Посмотреть»); «Памятки врача»; журнал «Решения и запросы» (голос
/// гражданина, свёрнут, в итоге — число записей); «Прошлые направления»; подвал с основой расчёта.
class RouteView extends StatefulWidget {
  const RouteView({super.key, required this.route, this.leaflets = const []});

  final PatientRoute route;

  /// Готовые памятки врача (`CitizenRouteController.leaflets`).
  final List<ScribeConsent> leaflets;

  @override
  State<RouteView> createState() => _RouteViewState();
}

class _RouteViewState extends State<RouteView> {
  final _testsOpen = ValueNotifier(false);
  final _testsKey = GlobalKey();

  @override
  void dispose() {
    _testsOpen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final route = widget.route;
    final seen = context.select<Session, String?>((session) => session.seenDecisionId);
    const gap = SizedBox(height: AppSpacing.md);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RouteHeadCard(route: route, stagesExpanded: actionCardOf(route, seenDecisionId: seen) == ActionCard.none),
        gap,
        for (final card in routeActionCards(context, route)) ...[card, gap],
        RouteNextCard(route: route, onSeeTests: () => revealSection(_testsKey, _testsOpen)),
        if (routeShowsForecast(route)) ...[gap, RouteForecastCard(route: route), gap, RouteFasterCard(route: route)],
        gap,
        CollapsibleSection(
          key: _testsKey,
          controller: _testsOpen,
          title: s.checklistSection,
          summary: s.routeChecklistSummary(route.expiredChecklistCount, route.validChecklistCount),
          origin: Origin.formula,
          child: ChecklistGroups(items: route.checklist, standard: route.standard),
        ),
        if (widget.leaflets.isNotEmpty) ...[gap, LeafletListCard(leaflets: widget.leaflets)],
        gap,
        CollapsibleSection(title: s.routeJournalHeading, summary: '${route.journal.length}', child: RouteJournal(entries: route.journal, voice: RouteVoice.citizen)),
        if (route.history.isNotEmpty) ...[gap, PastReferralsSection(history: route.history)],
        const SizedBox(height: AppSpacing.lg),
        Text(
          [if (route.basis.isNotEmpty) route.basis, s.myFootnoteSynthetic(routeDate(route.asOf)), s.stagesSource].join(' · '),
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}
