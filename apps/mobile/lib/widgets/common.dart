import 'package:flutter/material.dart';

import '../api/client.dart';
import '../api/models.dart';

String days(double? value) => value == null ? '—' : value.round().toString();
String pct(double? value) => value == null ? '—' : '${(value * 100).round()} %';

class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w600)),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, required this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) {
    if (error == null) return const SizedBox.shrink();
    final text = error is ApiException ? error.toString() : 'Сервер недоступен: $error';
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(padding: const EdgeInsets.all(12), child: Text(text)),
    );
  }
}

class ExplanationCard extends StatelessWidget {
  const ExplanationCard({super.key, required this.explanation, this.model});
  final Explanation explanation;
  final ModelInfo? model;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Почему так', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(explanation.summary),
            const Divider(),
            for (final f in explanation.factors)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(child: Text(f.text)),
                    Text(
                      '${f.contribution >= 0 ? '+' : '−'}${f.contribution.abs().toStringAsFixed(1)}',
                      style: TextStyle(color: f.contribution >= 0 ? Colors.red.shade700 : Colors.green.shade700),
                    ),
                  ],
                ),
              ),
            if (model != null) Text('Модель ${model!.name} ${model!.version}, обучена по ${model!.trainedThrough}', style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}
