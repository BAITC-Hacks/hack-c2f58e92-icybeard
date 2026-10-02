import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../app_card.dart';
import '../format.dart';
import '../hero_number.dart';
import '../inline_disclosure.dart';
import '../origin_tag.dart';

/// Карточки результата «Сколько ждут» (веб `WaitView.vue`): «В среднем по региону» и «Где быстрее в регионе» с
/// раскрывашкой «Как считается».

/// «В среднем по региону» (метка «прогноз модели»): сначала фраза, потом «≈ p50 дн.», ниже p90 и доля попавших в
/// больницу за 30 дней; под чертой — ориентир Минздрава с меткой «расчёт по правилу» и тихим «Источник»; подпись
/// «Оценка по очередям I квартала 2025 · данные на …». Названий и версий модели нет (X7).
class WaitAverageCard extends StatelessWidget {
  const WaitAverageCard({super.key, required this.prediction, this.target});

  final PredictResponse prediction;

  /// Ориентир Минздрава (`moh_target_wait_days`); null — строки нет.
  final RouteBenchmark? target;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final p = prediction;
    final asOf = p.model.trainedThrough;
    final target = this.target;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HeroNumber(
            label: s.waitRegionAverage,
            origin: Origin.ml,
            lead: s.waitHeroLead,
            value: approxDays(p.p50Days),
            unit: s.daysUnit,
            line: '${s.waitHeroNine(days(p.p90Days))}\n${s.waitHeroWithin30(pct(p.pWithin30Days))}',
          ),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: colors.borderSoft),
          const SizedBox(height: AppSpacing.md),
          if (target != null) ...[
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(s.benchmarkSentence(days(target.value)), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const OriginTag(Origin.formula),
              ],
            ),
            InlineDisclosure(
              title: s.sourceLabel,
              style: DisclosureStyle.quiet,
              divider: false,
              child: Text('${s.sourceLabel}: ${target.source}', style: theme.textTheme.labelSmall),
            ),
          ],
          Text([s.waitEstimateNote, if (asOf.isNotEmpty) s.asOfLabel(dateShort(asOf))].join(' · '), style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

/// «Где быстрее в регионе»: строки больниц ([bars] — `WaitBars` экрана) или пустой текст; ниже раскрывашка «Как
/// считается · место N из M регионов» с меткой «расчёт по правилу» и датой данных.
class WaitFasterCard extends StatelessWidget {
  const WaitFasterCard({super.key, required this.bars, required this.empty, this.index, this.indexTotal = 0, this.regionName, this.asOf, this.seasonal});

  final Widget bars;

  /// В регионе нет больниц с этим профилем.
  final bool empty;

  /// Индекс доступности выбранного региона; null — не показан (мало пациентов).
  final RegionIndex? index;
  final int indexTotal;
  final String? regionName;

  /// Дата данных модели (`model.trainedThrough`).
  final String? asOf;

  /// Сезонная строка NHS ([seasonalHint]); null — нет.
  final String? seasonal;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final index = this.index;
    final title = index == null ? s.howCounted : '${s.howCounted} · ${s.waitIndexSummary(index.rank, indexTotal)}';
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.waitFasterRegion),
          const SizedBox(height: AppSpacing.xs),
          if (empty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(s.noOrgsForProfile, style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.xs),
            Text(s.waitChangeProfileHint, style: theme.textTheme.labelSmall),
            const SizedBox(height: AppSpacing.sm),
          ] else
            bars,
          InlineDisclosure(
            title: title,
            style: DisclosureStyle.title,
            child: _HowPanel(index: index, total: indexTotal, regionName: regionName, seasonal: seasonal),
          ),
          // метка и дата в строку; при крупном казахском шрифте дата уходит строкой ниже
          SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.xs,
              children: [
                const OriginTag(Origin.formula),
                if (asOf != null && asOf!.isNotEmpty) Text(s.asOfLabel(dateShort(asOf)), style: theme.textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Панель «Как считается» (веб `citizen.wait.how*`): модель, индекс доступности, место региона (или почему не
/// показано) и сезонный пример NHS.
class _HowPanel extends StatelessWidget {
  const _HowPanel({this.index, required this.total, this.regionName, this.seasonal});

  final RegionIndex? index;
  final int total;
  final String? regionName;
  final String? seasonal;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final body = theme.textTheme.bodyMedium?.copyWith(height: 1.55);
    final muted = body?.copyWith(color: colors.muted);
    final index = this.index;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      decoration: BoxDecoration(color: colors.surfaceHover, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.waitHowIntro, style: body),
          const SizedBox(height: 10),
          Text(s.waitIndexExplain, style: body),
          const SizedBox(height: 10),
          if (index != null)
            Text(
              s.waitIndexHere(
                region: regionName ?? index.name,
                value: index.indexValue.toStringAsFixed(0),
                rank: index.rank,
                total: total,
                share: pct(index.shareOver30),
                p90: days(index.p90Days),
              ),
              style: body?.copyWith(fontWeight: FontWeight.w600),
            )
          else
            Text(s.waitIndexHidden, style: muted),
          if (seasonal != null) ...[
            const SizedBox(height: 10),
            Text('${s.waitSeasonal} $seasonal. ${s.waitSeasonalSuffix}', style: muted),
          ],
        ],
      ),
    );
  }
}
