import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';

/// Шаг памятки: заголовок (пусто — без заголовка) и текст.
typedef LeafletStep = ({String title, String body});

/// Разобранная памятка: первый абзац без заголовка — плашка «Что дальше» ([intro]), остальное — нумерованные шаги.
typedef LeafletDoc = ({String? intro, List<LeafletStep> steps});

final _blankLine = RegExp(r'\n\s*\n');

/// Разбор текста памятки как в LeafletView.vue: абзацы через пустую строку; у абзаца из нескольких строк первая
/// строка — заголовок шага, если кончается двоеточием или короче 60 знаков и записана заглавными; первый абзац без
/// заголовка — «Что дальше».
LeafletDoc parseLeaflet(String text) {
  final sections = <LeafletStep>[
    for (final block in text.split(_blankLine).map((b) => b.trim()).where((b) => b.isNotEmpty)) _section(block),
  ];
  final intro = sections.firstOrNull;
  if (intro != null && intro.title.isEmpty) {
    return (intro: intro.body, steps: List.unmodifiable(sections.skip(1)));
  }
  return (intro: null, steps: List.unmodifiable(sections));
}

LeafletStep _section(String block) {
  final lines = block.split('\n');
  final first = lines.first;
  final heading = lines.length > 1 && (first.endsWith(':') || (first.length < 60 && first == first.toUpperCase()));
  if (!heading) {
    return (title: '', body: block);
  }
  return (title: first.endsWith(':') ? first.substring(0, first.length - 1) : first, body: lines.skip(1).join('\n'));
}

/// Текст памятки: плашка «Что дальше: …» на accent-soft и нумерованные шаги с кружком 24 (public-leaflet-new).
class LeafletDocument extends StatelessWidget {
  const LeafletDocument({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final doc = parseLeaflet(text);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (doc.intro != null)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: colors.accentSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${s.myWhatNext}: ', style: const TextStyle(fontWeight: FontWeight.w700)),
                TextSpan(text: doc.intro),
              ]),
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
            ),
          ),
        for (final (i, step) in doc.steps.indexed) ...[
          const SizedBox(height: AppSpacing.md),
          _Step(number: i + 1, step: step),
        ],
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.step});

  final int number;
  final LeafletStep step;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: AppSizes.stageNode,
            height: AppSizes.stageNode,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colors.accentSoft),
            child: Text('$number', style: theme.textTheme.labelMedium?.copyWith(color: colors.accentHover).merge(AppType.numeric)),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (step.title.isNotEmpty) Text(step.title, style: theme.textTheme.titleSmall),
              if (step.body.isNotEmpty) Text(step.body, style: theme.textTheme.bodyMedium?.copyWith(height: 1.55)),
            ],
          ),
        ),
      ],
    );
  }
}
