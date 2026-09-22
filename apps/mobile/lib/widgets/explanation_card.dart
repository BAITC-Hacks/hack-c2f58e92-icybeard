import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'origin_tag.dart';

/// «Почему так»: вклад факторов в днях (SHAP той же модели). Плюс — дольше (danger), минус — быстрее (ok).
class ExplanationCard extends StatelessWidget {
  const ExplanationCard({super.key, required this.explanation, this.model});

  final Explanation explanation;
  final ModelInfo? model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.at(context);
    final tones = AppTones.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(s.whySo, style: theme.textTheme.titleMedium)),
                const OriginTag(Origin.ml),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(explanation.summary),
            const Divider(height: AppSpacing.lg),
            for (final factor in explanation.factors)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(factor.text)),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${factor.contribution >= 0 ? '+' : '−'}${factor.contribution.abs().toStringAsFixed(1)}',
                      style: theme.textTheme.bodyMedium?.merge(AppType.numeric).copyWith(color: factor.contribution >= 0 ? tones.danger.fg : tones.ok.fg),
                    ),
                  ],
                ),
              ),
            if (model != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(s.modelTrained(model!.name, model!.version, model!.trainedThrough), style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}
