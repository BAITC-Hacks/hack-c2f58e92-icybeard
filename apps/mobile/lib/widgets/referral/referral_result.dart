import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../empty_state.dart';
import '../format.dart';
import '../inline_disclosure.dart';
import '../kpi_tile.dart';
import '../route/forecast_factors.dart';
import '../skeleton.dart';
import 'referral_form.dart';

/// Карточка «Прогноз для «{организация}»» (веб: третий раздел ассистента) — всегда для организации, выбранной в
/// форме: четыре числа (половина ждёт, 9 из 10, место за 30 дней, риск отказа — словами для больницы вне
/// обучения), строка очереди, пояснение про слова вместо процента и «Из чего сложился прогноз» (кит). Пока считается —
/// скелетон; формы не хватает — «Выберите регион, организацию и профиль койки…».
class ReferralForecastCard extends StatelessWidget {
  const ReferralForecastCard({super.key, required this.busy, required this.prediction, required this.orgName, required this.factors});

  final bool busy;
  final PredictResponse? prediction;

  /// Короткое имя организации из формы.
  final String orgName;
  final List<ForecastFactorView> factors;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final p = prediction;
    if (p == null) {
      return busy ? const CardSkeleton(height: 220) : EmptyState(title: s.assistFillForm, icon: Icons.explore_outlined, compact: true);
    }
    final queue = p.queue;
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.assistForecastFor(orgName)),
          const SizedBox(height: AppSpacing.sm),
          StatGrid(items: [
            StatItem(label: s.assistHalf, value: approxDays(p.p50Days), unit: s.daysUnit),
            StatItem(label: s.assistNinety, value: approxDays(p.p90Days), unit: s.daysUnit),
            StatItem(label: s.assistWithin30, value: pct(p.pWithin30Days)),
            StatItem(label: s.assistRefusalRow, value: referralRisk(s, p.pRefusal, inTraining: p.refusalOrgInTraining)),
          ]),
          if (queue != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(s.assistQueueInfo(queue.len, days(queue.ageP50), queue.throughputPerDay.toStringAsFixed(1)), style: theme.textTheme.bodySmall),
          ],
          if (!p.refusalOrgInTraining) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(s.assistUnseenOrgHint, style: theme.textTheme.bodySmall),
          ],
          if (factors.isNotEmpty) InlineDisclosure(title: s.factorsTitle, child: ForecastFactorList(items: factors, lead: s.factorsLead)),
        ],
      ),
    );
  }
}

/// Карточка «Решение» (веб: четвёртый раздел): «Куда» — выбранная организация (и «вместо «…»», если выбрана
/// альтернатива), «Направление» — профиль · цель · МКБ-10, необязательная «Причина выбора» (Q-6), примечание про
/// ИС БГ и ссылки «Журнал решений» (после записи) и «К списку пациентов». Кнопка «Записать выбор» — в нижней зоне.
class ReferralDecisionCard extends StatelessWidget {
  const ReferralDecisionCard({
    super.key,
    required this.where,
    this.insteadOf,
    required this.what,
    required this.reason,
    this.reasonError,
    required this.locked,
    required this.recorded,
    required this.onJournal,
    required this.onWorklist,
  });

  final String where;
  final String? insteadOf;
  final String what;
  final TextEditingController reason;
  final String? reasonError;
  final bool locked;
  final bool recorded;
  final VoidCallback onJournal;
  final VoidCallback onWorklist;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.assistDecision),
          const SizedBox(height: AppSpacing.sm),
          _SummaryRow(
            label: s.assistSumWhere,
            child: Text.rich(TextSpan(children: [
              TextSpan(text: where),
              if (insteadOf != null) TextSpan(text: ' · ${s.assistSumInsteadOf(insteadOf!)}', style: TextStyle(color: colors.muted, fontWeight: FontWeight.w400)),
            ])),
          ),
          _SummaryRow(label: s.assistSumWhat, child: Text(what)),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: reason,
            enabled: !locked,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(labelText: s.assistReason, hintText: s.assistReasonExample, errorText: reasonError, alignLabelWithHint: true),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(s.assistSaveNote, style: theme.textTheme.labelSmall),
          const SizedBox(height: AppSpacing.sm),
          // ссылки-кнопки ≥ 44 dp (ArrowLink ниже нормы касания)
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              if (recorded) _Link(label: s.decisionsTitle, onTap: onJournal),
              _Link(label: s.assistToWorklist, onTap: onWorklist),
            ],
          ),
        ],
      ),
    );
  }
}

/// Ссылка «→» в виде текстовой кнопки (цель касания ≥ 44 dp).
class _Link extends StatelessWidget {
  const _Link({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) =>
      TextButton.icon(onPressed: onTap, icon: const Icon(Icons.arrow_forward, size: 18), iconAlignment: IconAlignment.end, label: Text(label));
}

/// Строка сводки: подпись слева (text-secondary), значение справа 600, линия border-soft снизу.
class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.borderSoft))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(constraints: const BoxConstraints(minWidth: 72, maxWidth: 110), child: Text(label, style: theme.textTheme.bodySmall)),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: DefaultTextStyle.merge(style: theme.textTheme.row, child: child)),
        ],
      ),
    );
  }
}
