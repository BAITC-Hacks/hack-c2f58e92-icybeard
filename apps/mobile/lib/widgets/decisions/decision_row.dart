import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../format.dart';
import '../picker_sheet.dart';
import 'decision_text.dart';

/// Строка журнала решений (веб: строка таблицы DecisionsView одной колонкой): объект решения (реф пациента или
/// «регион · профиль · дата»), что произошло (подпись журнала маршрута или «рекомендовано → выбрано»), дата
/// госпитализации, если она есть, строка «дата, время · предмет · итог» (итог словами; «выбрано иначе» — жирным) и
/// причина в кавычках. Тап — лист подробностей. Без номера записи и сырого JSON.
class DecisionRow extends StatelessWidget {
  const DecisionRow({super.key, required this.record, required this.names, required this.last, required this.onTap});

  final DecisionRecord record;
  final DecisionNames names;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final object = decisionObject(s, record, names);
    final what = decisionWhat(s, record, names);
    final planned = decisionPlanned(s, record);
    final reason = record.reason?.trim() ?? '';
    final differ = record.outcome == DecisionCodes.outcomeDiffer;
    final detail = theme.textTheme.rowDetail.copyWith(color: colors.muted).merge(AppType.numeric);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.row),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: last ? null : BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(object.isEmpty ? capitalizeFirst(s.decisionsSubject(record.subject)) : object,
                        style: theme.textTheme.rowStrong.merge(AppType.numeric), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (what != null) ...[
                      const SizedBox(height: 2),
                      Text(what, style: theme.textTheme.bodySmall?.copyWith(color: colors.ink), maxLines: 2, overflow: TextOverflow.ellipsis),
                    ],
                    if (planned != null) ...[const SizedBox(height: 2), Text(planned, style: detail)],
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: '${dateTimeShort(record.recordedAt)} · ${s.decisionsSubject(record.subject)} · '),
                        TextSpan(
                          text: s.decisionsOutcome(record.outcome),
                          style: differ ? TextStyle(color: colors.ink, fontWeight: FontWeight.w700) : null,
                        ),
                      ]),
                      style: detail,
                    ),
                    if (reason.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('«$reason»', style: detail, maxLines: 2, overflow: TextOverflow.ellipsis),
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

/// Лист подробностей записи (веб: боковая панель журнала): заголовок — предмет, подзаголовок — дата и время; строки
/// «Объект», «Рекомендовано», «Выбрано», «Итог», дата госпитализации (если есть) и серый блок «Причина» с полным
/// текстом. Номера записи нет (решение Q-8).
Future<void> showDecisionSheet(BuildContext context, DecisionRecord record, DecisionNames names) {
  final s = S.at(context);
  final planned = decisionPlanned(s, record);
  final object = decisionObject(s, record, names);
  return showInfoSheet(
    context,
    title: capitalizeFirst(s.decisionsSubject(record.subject)),
    subtitle: dateTimeShort(record.recordedAt),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailRow(label: s.subjectIdLabel, value: object.isEmpty ? '—' : object),
        _DetailRow(label: s.recommendedLabel, value: decisionRecommended(record, names)),
        _DetailRow(label: s.chosenLabel, value: decisionChosen(s, record, names), strong: true),
        _DetailRow(label: s.decisionsOutcomeLabel, value: s.decisionsOutcome(record.outcome)),
        if (planned != null) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Text(planned, style: Theme.of(context).textTheme.bodySmall)),
        const SizedBox(height: AppSpacing.lg),
        _ReasonBlock(text: record.reason?.trim() ?? ''),
      ],
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.strong = false});

  final String label;
  final String value;
  final bool strong;

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
          Expanded(flex: 2, child: Text(label, style: theme.textTheme.bodySmall)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 3,
            child: SelectableText(value, textAlign: TextAlign.end, style: (strong ? theme.textTheme.rowStrong : theme.textTheme.row).merge(AppType.numeric)),
          ),
        ],
      ),
    );
  }
}

/// Серый блок «Причина» с полным текстом (или «—»).
class _ReasonBlock extends StatelessWidget {
  const _ReasonBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: colors.neutralSoft, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.reasonShort.toUpperCase(), style: theme.textTheme.overline.copyWith(color: colors.muted)),
          const SizedBox(height: AppSpacing.xs),
          SelectableText(text.isEmpty ? '—' : text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
