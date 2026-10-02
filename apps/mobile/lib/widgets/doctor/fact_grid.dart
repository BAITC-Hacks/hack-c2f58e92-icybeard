import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../status_chip.dart';

/// Факт маршрута для [FactGrid]: подпись и значение; [tone] danger красит значение (риск отказа выше 20 %).
@immutable
class RouteFact {
  const RouteFact(this.label, this.value, {this.tone});

  final String label;
  final String value;
  final StatusTone? tone;
}

/// Факты маршрута пациента в две колонки (веб `who-facts` и `h-stats` страницы пациента): подпись 12 text-secondary
/// над значением 16.5/800 табличными цифрами одной строкой (у общего `StatGrid` значение 19/800 и единица отдельно),
/// ячейки разделены линиями border-soft; риск отказа выше 20 % красный, как в вебе.
class FactGrid extends StatelessWidget {
  const FactGrid({super.key, required this.facts});

  final List<RouteFact> facts;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final line = BorderSide(color: colors.borderSoft);
    Widget cell(RouteFact fact, {required bool first}) => Container(
          padding: EdgeInsets.fromLTRB(first ? 0 : AppSpacing.md, 10, AppSpacing.sm, 10),
          decoration: BoxDecoration(border: first ? null : Border(left: line)),
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fact.label, style: theme.textTheme.labelSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  fact.value,
                  style: theme.textTheme.titleMedium?.copyWith(color: fact.tone == StatusTone.danger ? colors.danger : null).merge(AppType.numeric),
                ),
              ],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var start = 0; start < facts.length; start += 2)
          Container(
            decoration: BoxDecoration(border: start == 0 ? null : Border(top: line)),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cell(facts[start], first: true)),
                  Expanded(child: start + 1 < facts.length ? cell(facts[start + 1], first: false) : const SizedBox.shrink()),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
