import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'origin_tag.dart';
import 'status_chip.dart';

/// Ряд плиток одной высоты: подпись в одной плитке переносится на вторую строку — остальные вытягиваются за ней.
/// [columns] — сколько плиток в ряду (по умолчанию все в один ряд); неполный последний ряд держит ширину колонки.
/// С фразами-подписями на 360 dp — две колонки.
class KpiRow extends StatelessWidget {
  const KpiRow({super.key, required this.children, this.columns});

  final List<Widget> children;
  final int? columns;

  @override
  Widget build(BuildContext context) {
    final perRow = (columns == null || columns! < 1) ? children.length : columns!;
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    final rows = [for (var start = 0; start < children.length; start += perRow) children.sublist(start, (start + perRow).clamp(0, children.length))];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, row) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: AppSpacing.sm),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var j = 0; j < perRow; j++) ...[
                  if (j > 0) const SizedBox(width: AppSpacing.sm),
                  Expanded(child: j < row.length ? row[j] : const SizedBox.shrink()),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Плитка показателя (веб KpiTile) на surface-sunken radius 12: значение 22/800 табличными цифрами с единицей
/// 13.5. Подпись по умолчанию под значением (12 text-secondary, до двух строк, метка происхождения ниже); [labelFirst]
/// — подпись фразой над значением 13.5/600 text-secondary с меткой в той же строке (веб `labelFirst`). [hint] —
/// пояснение 12 под всем; [tone] красит значение: ok — зелёный, warn — янтарный, danger — красный.
class KpiTile extends StatelessWidget {
  const KpiTile({super.key, required this.value, required this.label, this.unit, this.origin, this.labelFirst = false, this.hint, this.tone});

  final String value;
  final String label;
  final String? unit;
  final Origin? origin;
  final bool labelFirst;
  final String? hint;
  final StatusTone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final valueColor = _valueColor(colors, tone);
    final valueRow = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(child: Text(value, style: theme.textTheme.headlineSmall?.copyWith(color: valueColor).merge(AppType.numeric), overflow: TextOverflow.ellipsis)),
        if (unit != null) ...[const SizedBox(width: AppSpacing.xs), Text(unit!, style: theme.textTheme.bodySmall)],
      ],
    );
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: colors.surfaceSunken, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: labelFirst
            ? [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(label, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, height: 1.35)),
                    if (origin != null) OriginTag(origin!),
                  ],
                ),
                const SizedBox(height: 10),
                valueRow,
                if (hint != null && hint!.isNotEmpty) ...[const SizedBox(height: AppSpacing.xs), Text(hint!, style: theme.textTheme.labelSmall)],
              ]
            : [
                valueRow,
                const SizedBox(height: AppSpacing.xs),
                Text(label, style: theme.textTheme.labelSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (origin != null) ...[const SizedBox(height: AppSpacing.sm), OriginTag(origin!)],
                if (hint != null && hint!.isNotEmpty) ...[const SizedBox(height: AppSpacing.xs), Text(hint!, style: theme.textTheme.labelSmall)],
              ],
      ),
    );
  }
}

/// Цвет значения показателя по тону: ok — зелёный, warn — янтарный, danger — красный; иначе — цвет стиля.
Color? _valueColor(ColorTokens colors, StatusTone? tone) => switch (tone) {
      StatusTone.ok => colors.ok,
      StatusTone.warn => colors.warn,
      StatusTone.danger => colors.danger,
      _ => null,
    };

/// Показатель сетки [StatGrid]: подпись, значение и необязательная единица; [tone] красит значение, как у [KpiTile].
class StatItem {
  const StatItem({required this.label, required this.value, this.unit, this.tone});

  final String label;
  final String value;
  final String? unit;
  final StatusTone? tone;
}

/// Сетка показателей без плиток (веб `.h-stats` на маршруте пациента и в ассистенте направления): подпись 12
/// text-secondary над значением 19/800 с единицей 13.5/700 (тон значения — у [StatItem]); ячейки разделены линиями
/// `--border-soft`, по [columns] в ряду (на телефоне — две). Для прогнозных чисел врача вместо ряда [KpiTile].
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.items, this.columns = 2});

  final List<StatItem> items;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final perRow = columns < 1 ? 1 : columns;
    final line = BorderSide(color: colors.borderSoft);
    Widget cell(StatItem item, {required bool first}) => Container(
          padding: EdgeInsets.fromLTRB(first ? 0 : AppSpacing.md, 10, AppSpacing.sm, 10),
          decoration: BoxDecoration(border: first ? null : Border(left: line)),
          child: Semantics(
            container: true,
            label: '${item.label}: ${item.value}${item.unit == null ? '' : ' ${item.unit}'}',
            excludeSemantics: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.label, style: theme.textTheme.labelSmall),
                const SizedBox(height: AppSpacing.xs),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: item.value),
                    if (item.unit != null) TextSpan(text: ' ${item.unit}', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
                  ]),
                  style: theme.textTheme.titleLarge?.copyWith(color: _valueColor(colors, item.tone)).merge(AppType.numeric),
                ),
              ],
            ),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var start = 0; start < items.length; start += perRow)
          Container(
            decoration: BoxDecoration(border: start == 0 ? null : Border(top: line)),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var j = 0; j < perRow; j++)
                    Expanded(child: start + j < items.length ? cell(items[start + j], first: j == 0) : const SizedBox.shrink()),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
