import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'app_card.dart';
import 'origin_tag.dart';

final _parenthesized = RegExp(r'\s*\([^)]*\)\s*$');

/// Факторы «Почему так» строками: подпись слева, вклад в днях справа табличными цифрами. Плюс — дольше (coral-text),
/// минус — быстрее (sage). Первой строкой — базовое ожидание из сводки модели.
class FactorList extends StatelessWidget {
  const FactorList({super.key, required this.explanation, this.model});

  final Explanation explanation;
  final ModelInfo? model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.at(context);
    final tones = AppTones.of(context);
    final base = explanation.summary.split(',').first.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (base.isNotEmpty) Text(base, style: theme.textTheme.row.merge(AppType.numeric)),
        for (final factor in explanation.factors)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(factor.text.replaceFirst(_parenthesized, ''), style: theme.textTheme.bodySmall)),
                const SizedBox(width: AppSpacing.md),
                Text(
                  '${factor.contribution >= 0 ? '+' : '−'}${factor.contribution.abs().toStringAsFixed(1)} ${s.daysUnit}',
                  style: theme.textTheme.rowStrong.merge(AppType.numeric).copyWith(color: factor.contribution >= 0 ? tones.danger.fg : tones.ok.fg),
                ),
              ],
            ),
          ),
        if (model != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(s.modelTrained(model!.name, model!.version, model!.trainedThrough), style: theme.textTheme.labelSmall),
        ],
      ],
    );
  }
}

/// Карточка «Почему так» с меткой ML-модели — для ассистента направления, где факторы показаны сразу.
class ExplanationCard extends StatelessWidget {
  const ExplanationCard({super.key, required this.explanation, this.model});

  final Explanation explanation;
  final ModelInfo? model;

  @override
  Widget build(BuildContext context) => AppCard(
        padding: AppCard.plain,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CardLabel(S.at(context).whySo, trailing: const OriginTag(Origin.ml)),
            const SizedBox(height: AppSpacing.md),
            FactorList(explanation: explanation, model: model),
          ],
        ),
      );
}
