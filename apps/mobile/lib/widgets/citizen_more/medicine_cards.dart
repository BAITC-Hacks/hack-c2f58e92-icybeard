import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../format.dart';
import '../inline_disclosure.dart';
import '../origin_tag.dart';
import '../status_chip.dart';
import 'medicines_api.dart';

/// Карточки результата «Проверка рецепта» (веб `MedicinesView.vue`, M-1…M-5): покрытие, сроки получения, дефицит и
/// «Как считается» в одной карточке; ниже «Другие МНН при этой нозологии».

/// Карточка МНН: заголовок, чип покрытия (покрыт — зелёный, не покрыт — янтарный), метка происхождения (модель,
/// если есть модельная оценка, иначе правило), строка программы; фактическая медиана, «9 из 10 получают», «Получают
/// за 14 дней» с полосой; модельная оценка p50 — отдельной строкой со своей меткой, не вместо факта; дефицит словами
/// с долей похожих МНН; «Как считается» — текст веба и основания расчёта.
class MedicineResultCard extends StatelessWidget {
  const MedicineResultCard({super.key, required this.result, required this.title, this.nosologyId});

  final MedicineCheck result;

  /// «МНН 1201» или «Нозология 9».
  final String title;
  final String? nosologyId;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final data = result.check;
    final peer = result.peerRatio;
    final details = [
      data.covered ? s.medCoveredBy(data.program ?? '') : s.medNotCoveredTitle,
      if (data.category != null && data.category!.isNotEmpty) s.medCategory(data.category!),
      if (nosologyId != null) s.medNosology(nosologyId!),
    ].join(' · ');
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              StatusChip(data.covered ? s.medCovered : s.medNotCovered, tone: data.covered ? StatusTone.ok : StatusTone.warn),
              OriginTag(originModelOrRule(data.fillDaysP50Model != null), note: s.medCoverageNote),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(details, style: theme.textTheme.bodySmall?.merge(AppType.numeric)),
          const SizedBox(height: AppSpacing.xs),
          ListRow(title: s.medMedian, trailing: RowValue(daysWithUnit(data.fillDaysP50, s), strong: true)),
          ListRow(title: s.fillNine, trailing: RowValue(data.fillDaysP90 == null ? '—' : s.upToDays(days(data.fillDaysP90)), strong: true)),
          _ShareRow(title: s.medWithin14, share: data.pFilled14d),
          if (data.fillDaysP50Model != null) _ModelRow(days: daysWithUnit(data.fillDaysP50Model, s)),
          _ShortageRow(flag: data.shortage.flag, peerRatio: peer),
          InlineDisclosure(
            title: s.howCounted,
            style: DisclosureStyle.title,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.medHowPlain(dateShort(data.model?.trainedThrough)), style: theme.textTheme.bodyMedium?.copyWith(height: 1.55)),
                  if (data.basis.isNotEmpty) ...[const SizedBox(height: AppSpacing.sm), Text('• ${_sentence(s.medBasisFill, data.basis)}', style: theme.textTheme.bodySmall)],
                  if (data.shortage.basis.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text('• ${_sentence(s.medBasisShortage, data.shortage.basis)}', style: theme.textTheme.bodySmall?.copyWith(color: colors.muted)),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// «Сроки — медиана … месяцев.»: подпись и основание сервера без точки в конце, точка — одна (веб `sentence`).
  static String _sentence(String label, String text) => '$label ${text.trim().replaceFirst(RegExp(r'[.\s]+$'), '')}.';
}

/// «Получают за 14 дней»: доля справа accent и тонкая полоса под строкой.
class _ShareRow extends StatelessWidget {
  const _ShareRow({required this.title, required this.share});

  final String title;
  final double? share;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.row),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.row)),
              const SizedBox(width: AppSpacing.md),
              RowValue(pct(share), strong: true, color: colors.accentHover),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.xs),
              child: LinearProgressIndicator(value: (share ?? 0).clamp(0.0, 1.0), minHeight: 4, color: colors.accent, backgroundColor: colors.neutralSoft),
            ),
          ),
        ],
      ),
    );
  }
}

/// «Дефицит»: «Похожие МНН обеспечены N %» (если есть похожие с данными) и чип «признаки дефицита» (красный) /
/// «без признаков дефицита» (зелёный). Балл дефицита не показывается — его нет и в вебе.
class _ShortageRow extends StatelessWidget {
  const _ShortageRow({required this.flag, this.peerRatio});

  final bool flag;
  final double? peerRatio;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    // при крупном казахском шрифте чип переносится под подпись, а не выталкивает её за край
    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.row),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: SizedBox(
        width: double.infinity,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.shortageSection, style: theme.textTheme.row),
                if (peerRatio != null) Text('${s.medPeerShortage} ${pct(peerRatio)}', style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
              ],
            ),
            StatusChip(flag ? s.medShortageFlag : s.medNoShortageFlag, tone: flag ? StatusTone.danger : StatusTone.ok),
          ],
        ),
      ),
    );
  }
}

/// «Модельная оценка p50» с меткой «прогноз модели» под подписью (рядом с фактом, не вместо него) и днями справа.
class _ModelRow extends StatelessWidget {
  const _ModelRow({required this.days});

  final String days;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final colors = AppPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: AppSizes.row),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.medModelP50, style: Theme.of(context).textTheme.row),
                const SizedBox(height: AppSpacing.xs),
                OriginTag(Origin.ml, note: s.medModelP50Note),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          RowValue(days, strong: true),
        ],
      ),
    );
  }
}

/// «Другие МНН при этой нозологии»: название и «N рецептов в год», тап выбирает МНН; внизу — когда появятся аптеки.
class OtherMnnCard extends StatelessWidget {
  const OtherMnnCard({super.key, required this.items, required this.onPick});

  final List<OtherMnn> items;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.medOtherMnn),
          if (items.isEmpty)
            Padding(padding: const EdgeInsets.symmetric(vertical: AppSpacing.md), child: Text(s.routeNoData, style: theme.textTheme.bodySmall))
          else
            for (final (i, m) in items.indexed)
              ListRow(title: m.name, subtitle: s.medPerYear(thousands(m.issued12m)), last: i == items.length - 1, onTap: () => onPick(m.mnnId)),
          const SizedBox(height: AppSpacing.sm),
          Text(s.medPharmaciesHint, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}
