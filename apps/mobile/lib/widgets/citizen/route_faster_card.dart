import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../state/session.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../app_card.dart';
import '../origin_tag.dart';
import '../route/alternative_tile.dart';
import 'citizen_action_button.dart';
import 'citizen_actions.dart';
import 'citizen_route_rules.dart';

/// «Где быстрее» (RouteCitizenView.vue, блок F): больницы региона с тем же профилем плитками комплекта маршрута —
/// без заблокированных для маршрута (`offeredAlternatives`); «Попросить рассмотреть» — только при
/// `request_transfer` (лист с необязательным комментарием, Q20), у запрошенной — чип «Запрос отправлен»; вне листа
/// ожидания своей больницы — «Сейчас просить о переводе нельзя…»; блок «Не хотите переводиться?» (F8). Больнице
/// соседнего региона подписывается «сосед: {регион}» — название из справочника регионов, он читается один раз и
/// только когда такая больница есть. Скрыт после подтверждённого перевода (Q18).
class RouteFasterCard extends StatefulWidget {
  const RouteFasterCard({super.key, required this.route});

  final PatientRoute route;

  @override
  State<RouteFasterCard> createState() => _RouteFasterCardState();
}

class _RouteFasterCardState extends State<RouteFasterCard> {
  Map<String, String> _regions = const {};
  String? _regionsLocale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadRegions();
  }

  @override
  void didUpdateWidget(RouteFasterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadRegions();
  }

  /// Названия регионов — только если среди плиток есть соседний регион; заново — при смене языка. Сбой справочника
  /// не мешает: плитка покажет только код.
  Future<void> _loadRegions() async {
    final session = context.read<Session>();
    final locale = session.locale;
    final needed = widget.route.offeredAlternatives.any((a) => a.isNeighborRegion && a.regionKato != null);
    if (!needed || _regionsLocale == locale) {
      return;
    }
    _regionsLocale = locale;
    try {
      final regions = await session.api.regions();
      if (mounted) {
        setState(() => _regions = {for (final r in regions) r.kato: r.name});
      }
    } on Exception {
      _regionsLocale = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final route = widget.route;
    final offered = route.offeredAlternatives;
    final origin = originModelOnly(route.alternativesModel != null);
    final canRequest = route.can(RouteCodes.actionRequestTransfer);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.myFasterTitle, trailing: origin == null ? null : OriginTag(origin)),
          const SizedBox(height: AppSpacing.xs),
          Text(s.myFasterLead, style: theme.textTheme.bodySmall),
          if (offered.isEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(s.routeNoAlternatives, style: theme.textTheme.bodySmall),
          ],
          for (final alternative in offered) ...[
            const SizedBox(height: AppSpacing.md),
            AlternativeTile(
              alternative: alternative,
              baselineDays: route.forecast.p50Days,
              neighbourRegion: _regions[alternative.regionKato],
              requested: route.openRequest?.toMoCode == alternative.moCode,
              action: canRequest
                  ? CitizenActionButton(label: s.routeRequestConsider, kind: CitizenButtonKind.link, onPressed: () => requestTransfer(context, alternative))
                  : null,
            ),
          ],
          if (routeRequestsClosed(route)) ...[
            const SizedBox(height: AppSpacing.md),
            Text(s.myRequestsClosed, style: theme.textTheme.bodySmall),
          ],
          if (routeShowsStayBlock(route)) ...[const SizedBox(height: AppSpacing.md), _StayBlock(route: route)],
        ],
      ),
    );
  }
}

/// «Не хотите переводиться?» (F8): серая плашка; выбор уже сделан — галочка и «Вы остаётесь в своей больнице…»;
/// «Хочу остаться в своей больнице» (`prefer_current`), «Больше не нужно» (через лист подтверждения) и подсказка,
/// чем они отличаются.
class _StayBlock extends StatelessWidget {
  const _StayBlock({required this.route});

  final PatientRoute route;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: colors.surfaceSunken, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.myStayTitle, style: theme.textTheme.titleSmall),
          if (route.progress?.prefersCurrent ?? false) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Icon(Icons.check_circle_outline, size: 20, color: AppTones.of(context).ok.fg)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: Text(s.myStayDone, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ],
          if (route.can(RouteCodes.actionPreferCurrent)) ...[
            const SizedBox(height: AppSpacing.sm),
            CitizenActionButton(
              label: s.myStay,
              icon: Icons.home_outlined,
              kind: CitizenButtonKind.secondary,
              compact: true,
              onPressed: () => preferCurrent(context),
            ),
          ],
          if (routeShowsWithdrawInStay(route)) ...[
            const SizedBox(height: AppSpacing.sm),
            CitizenActionButton(
              label: s.validationWithdraw,
              icon: Icons.cancel_outlined,
              kind: CitizenButtonKind.danger,
              compact: true,
              onPressed: () => withdrawFromList(context),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(s.myStayHint, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
