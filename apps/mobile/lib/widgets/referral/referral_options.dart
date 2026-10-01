import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../format.dart';
import '../origin_tag.dart';
import 'referral_form.dart';
import 'referral_params.dart';

/// Карточка «Куда направить» (веб: второй раздел ассистента). До прогноза — выбор организации («Выберите
/// организацию»); после — варианты одной колонкой: первой организация врача («{код} · выбрана врачом · в очереди N ·
/// риск отказа …»), затем альтернативы («{код} · сосед: {регион} · на N дн. быстрее/дольше · риск отказа N %»), у
/// каждой «половина ждёт ≈ N дн.» (зелёным, если быстрее). Выбор — [onChoose]; после записи решения варианты
/// заблокированы ([locked]); «Сменить организацию» возвращает к выбору.
class ReferralWhereCard extends StatelessWidget {
  const ReferralWhereCard({
    super.key,
    required this.form,
    required this.prediction,
    required this.alternatives,
    required this.chosen,
    required this.orgName,
    required this.regionName,
    required this.canPick,
    required this.locked,
    required this.onPickOrg,
    required this.onChangeOrg,
    required this.onChoose,
  });

  final ReferralForm form;
  final PredictResponse? prediction;
  final List<Alternative> alternatives;
  final String chosen;

  /// Полное имя организации врача по коду (или сам код).
  final String orgName;

  /// Имя региона по коду КАТО; null — неизвестен.
  final String? Function(String? kato) regionName;
  final bool canPick;
  final bool locked;
  final VoidCallback onPickOrg;
  final VoidCallback onChangeOrg;
  final ValueChanged<String> onChoose;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final p = prediction;
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.assistWhere, trailing: p == null ? null : const OriginTag(Origin.ml)),
          const SizedBox(height: AppSpacing.sm),
          if (p == null || form.moCode.isEmpty)
            ReferralSelect(value: form.moCode.isEmpty ? null : shortOrgName(orgName), placeholder: s.assistPickOrg, onTap: onPickOrg, enabled: canPick)
          else ...[
            _Option(
              selected: chosen == form.moCode,
              locked: locked,
              name: shortOrgName(orgName),
              lines: [
                TextSpan(text: '${form.moCode} · ${s.assistChosenByDoctor}${p.queue == null ? '' : ' · ${s.assistInQueue(p.queue!.len)}'} · '),
                _risk(context, s.assistRefusal(referralRisk(s, p.pRefusal, inTraining: p.refusalOrgInTraining)), referralRiskHigh(p.pRefusal)),
              ],
              days: p.p50Days,
              faster: false,
              onTap: () => onChoose(form.moCode),
            ),
            for (final a in alternatives)
              _Option(
                selected: chosen == a.moCode,
                locked: locked,
                name: shortOrgName(a.name),
                lines: _alternativeLine(context, s, a, p),
                days: a.p50Days,
                faster: (roundedDaysDiff(p.p50Days, a.p50Days) ?? 0) > 0,
                onTap: () => onChoose(a.moCode),
              ),
            if (alternatives.isEmpty) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(s.routeNoAlternatives, style: Theme.of(context).textTheme.bodySmall)),
            Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: locked ? null : onChangeOrg, child: Text(s.assistChangeOrg))),
          ],
        ],
      ),
    );
  }

  List<InlineSpan> _alternativeLine(BuildContext context, S s, Alternative a, PredictResponse p) {
    final region = a.isNeighborRegion ? regionName(a.regionKato) : null;
    final compare = referralCompare(s, p.p50Days, a.p50Days);
    final faster = (roundedDaysDiff(p.p50Days, a.p50Days) ?? 0) > 0;
    return [
      TextSpan(text: a.moCode),
      if (region != null) TextSpan(text: ' · ${s.routeNeighbourRegion(region)}'),
      if (compare != null) ...[
        const TextSpan(text: ' · '),
        TextSpan(text: compare, style: faster ? TextStyle(color: AppTones.of(context).ok.fg) : null),
      ],
      const TextSpan(text: ' · '),
      _risk(context, s.assistRefusal(pct(a.pRefusal)), referralRiskHigh(a.pRefusal)),
    ];
  }

  static TextSpan _risk(BuildContext context, String text, bool high) => TextSpan(text: text, style: high ? TextStyle(color: AppTones.of(context).danger.fg) : null);
}

/// Вариант выбора: кружок выбора, короткое имя, строка кода и сравнений, «половина ждёт ≈ N дн.».
class _Option extends StatelessWidget {
  const _Option({
    required this.selected,
    required this.locked,
    required this.name,
    required this.lines,
    required this.days,
    required this.faster,
    required this.onTap,
  });

  final bool selected;
  final bool locked;
  final String name;
  final List<InlineSpan> lines;
  final double days;
  final bool faster;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final muted = theme.textTheme.labelSmall?.merge(AppType.numeric);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      enabled: !locked,
      child: Material(
        color: selected ? colors.accentSubtle : ColorTokens.transparent,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.md),
          onTap: locked ? null : onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: AppSizes.row),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 22, color: selected ? colors.accent : colors.muted),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.row, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 2),
                      Text.rich(TextSpan(children: lines), style: muted),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(children: [
                          TextSpan(text: '${s.assistHalfShort} '),
                          TextSpan(
                            text: '${approxDays(days)} ${s.daysUnit}',
                            style: theme.textTheme.labelMedium?.copyWith(color: faster ? AppTones.of(context).ok.fg : colors.ink),
                          ),
                        ]),
                        style: muted,
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
