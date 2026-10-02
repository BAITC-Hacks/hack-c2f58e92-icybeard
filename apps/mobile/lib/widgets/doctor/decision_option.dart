import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../format.dart';
import '../status_chip.dart';

/// Вариант перевода в карточке «Оставить или перевести»: больница, её прогноз (нет у больницы только из запроса
/// пациента) и метка «просит пациент».
@immutable
class DecisionChoice {
  const DecisionChoice({required this.moCode, required this.name, this.alternative, this.requested = false});

  final String moCode;
  final String name;

  /// Прогноз больницы из альтернатив маршрута; null — больница есть только в запросе пациента.
  final Alternative? alternative;

  /// Эту больницу пациент попросил рассмотреть (открытый `request_redirect`).
  final bool requested;
}

/// Варианты перевода (Q-5): альтернативы маршрута без отказавших и отклонённых пациентом больниц
/// (`offeredAlternatives`), у запрошенной — метка; больница из открытого запроса пациента, которой нет среди
/// альтернатив, — последней, без прогнозных чисел. Можно ли её предложить, решает сервер (409 с текстом).
List<DecisionChoice> decisionChoices(PatientRoute route) {
  final request = route.openRequest;
  final requested = request?.toMoCode ?? '';
  final offered = route.offeredAlternatives;
  return [
    for (final a in offered) DecisionChoice(moCode: a.moCode, name: a.name, alternative: a, requested: a.moCode == requested),
    if (requested.isNotEmpty && !offered.any((a) => a.moCode == requested))
      DecisionChoice(moCode: requested, name: request?.toMoName ?? requested, requested: true),
  ];
}

/// Строка выбора больницы (веб `.option` с радио): кружок выбора, короткое имя и «просит пациент», ниже «код ·
/// сосед: регион · 9 из 10 ждут до N дн. · риск отказа X %» (риск красным выше 20 %) и зелёное «половина ждёт ≈ N
/// дн.». Тап по выбранной строке снимает выбор. Цель нажатия — вся строка, не меньше 56.
class DecisionOptionTile extends StatelessWidget {
  const DecisionOptionTile({super.key, required this.choice, required this.selected, required this.onTap, this.neighbourRegion, this.last = false});

  final DecisionChoice choice;
  final bool selected;
  final VoidCallback? onTap;

  /// Название соседнего региона для «сосед: …»; null — больница своего региона.
  final String? neighbourRegion;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final alt = choice.alternative;
    final detail = theme.textTheme.rowDetail.copyWith(color: colors.muted).merge(AppType.numeric);
    final head = [
      choice.moCode,
      if (neighbourRegion != null) s.routeNeighbourRegion(neighbourRegion!),
      if (alt != null) s.patientRouteAltNine(days(alt.p90Days)),
    ].join(' · ');
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: selected,
        inMutuallyExclusiveGroup: true,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSizes.row),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: selected ? colors.accentSubtle : null,
              border: last ? null : Border(bottom: BorderSide(color: colors.borderSoft)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 22, color: selected ? colors.accent : colors.muted),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(shortOrgName(choice.name), style: theme.textTheme.row),
                          if (choice.requested) StatusChip(s.patientRouteRequested, tone: StatusTone.warn),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: head),
                          if (alt != null) ...[
                            const TextSpan(text: ' · '),
                            TextSpan(
                              text: s.patientRouteAltRefusal(pct(alt.pRefusal)),
                              style: refusalHigh(alt.pRefusal) ? TextStyle(color: colors.danger) : null,
                            ),
                          ],
                        ]),
                        style: detail,
                      ),
                      if (alt != null)
                        Text(
                          '${s.patientRouteHalfShort} ${approxDays(alt.p50Days)} ${s.daysUnit}',
                          style: theme.textTheme.rowDetail.copyWith(color: colors.ok, fontWeight: FontWeight.w700).merge(AppType.numeric),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
