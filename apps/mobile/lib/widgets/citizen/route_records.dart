import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../collapsible_section.dart';
import '../format.dart';
import '../status_chip.dart';

/// «Памятки врача» (F14, RouteCitizenView.vue `leaflets`): по строке на утверждённую запись приёма — короткое имя
/// больницы, дата утверждения и «Открыть →» в читалку `/home/route/leaflet/:token`.
class LeafletListCard extends StatelessWidget {
  const LeafletListCard({super.key, required this.leaflets});

  /// `CitizenRouteController.leaflets` — завершённые записи с токеном.
  final List<ScribeConsent> leaflets;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.myLeafletsTitle),
          for (final (i, leaflet) in leaflets.indexed)
            ListRow(
              title: shortOrgName(leaflet.moName ?? ''),
              subtitle: dateShort(leaflet.approvedAt),
              trailing: ArrowLink(s.myLeafletOpen),
              chevron: false,
              last: i == leaflets.length - 1,
              onTap: () => context.go('/home/route/leaflet/${Uri.encodeComponent(leaflet.leafletToken ?? '')}'),
            ),
        ],
      ),
    );
  }
}

/// «Прошлые направления» (RouteHistory.vue) — свёрнутая секция с числом в итоге: «дата · профиль», больница, справа
/// исход («Госпитализация» / «Отказ») и «ждал N дн.».
class PastReferralsSection extends StatelessWidget {
  const PastReferralsSection({super.key, required this.history});

  final List<RouteHistoryItem> history;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    return CollapsibleSection(
      title: s.pastReferrals,
      summary: '${history.length}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, item) in history.indexed)
            ListRow(
              title: '${routeDate(item.registeredAt)} · ${item.profileName}',
              subtitle: shortOrgName(item.moName),
              last: i == history.length - 1,
              trailing: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  item.outcome == RouteCodes.hospitalized
                      ? StatusChip(s.outcomeHospitalized, tone: StatusTone.ok)
                      : StatusChip(s.outcomeRefused, tone: StatusTone.danger),
                  const SizedBox(height: AppSpacing.xs),
                  Text(s.waitedDays(item.waitDays), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
