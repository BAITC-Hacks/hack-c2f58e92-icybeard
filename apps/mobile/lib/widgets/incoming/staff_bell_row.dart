import 'package:flutter/material.dart';

import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';

/// Строка уведомления персонала (веб `NotificationBell.vue`, `.bell-item`): круг 32 со значком accent-soft /
/// accent-strong, текст 14.5/600, комментарий пациента «…» курсивом, плашка с эпикризом выписки под подписью (Q-7),
/// мелкая строка «реф · дата, время». Нажатие — по всей строке (не меньше 56): отметить прочитанным и открыть экран.
/// Разделитель снизу, кроме [last].
class StaffBellRow extends StatelessWidget {
  const StaffBellRow({
    super.key,
    required this.icon,
    required this.title,
    this.comment,
    this.summaryLabel,
    this.summary,
    this.meta,
    required this.onTap,
    this.last = false,
  });

  final IconData icon;
  final String title;

  /// Комментарий пациента — показывается в кавычках-ёлочках курсивом.
  final String? comment;

  /// Подпись плашки с текстом [summary] (эпикриз выписки).
  final String? summaryLabel;
  final String? summary;

  /// «реф · дата, время» или только момент события.
  final String? meta;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final tone = AppTones.of(context).accent;
    final note = comment?.trim();
    final text = summary?.trim();
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.row),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: last ? null : BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(
                child: Container(
                  width: AppSizes.small - 4,
                  height: AppSizes.small - 4,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: tone.bg),
                  child: Icon(icon, size: 16, color: tone.fg),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.row),
                    if (note != null && note.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('«$note»', style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                    ],
                    if (text != null && text.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.sm),
                      _SummaryPlate(label: summaryLabel, text: text),
                    ],
                    if (meta != null && meta!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(meta!, style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Icon(Icons.chevron_right, size: 20, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плашка с текстом врача (эпикриз): подпись-kicker и сам текст целиком — он нужен врачу-отправителю прямо в
/// уведомлении (Q-7).
class _SummaryPlate extends StatelessWidget {
  const _SummaryPlate({required this.label, required this.text});

  final String? label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(color: colors.surfaceSunken, borderRadius: BorderRadius.circular(AppRadius.plate)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null) ...[
            Text(label!.toUpperCase(), style: theme.textTheme.overline.copyWith(color: colors.muted)),
            const SizedBox(height: AppSpacing.xs),
          ],
          Text(text, style: theme.textTheme.bodySmall?.copyWith(color: colors.ink)),
        ],
      ),
    );
  }
}
