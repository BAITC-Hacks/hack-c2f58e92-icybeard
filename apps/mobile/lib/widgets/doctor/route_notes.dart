import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../format.dart';

/// Открытый запрос пациента на плашке (веб `.signal` карточек решения и перевода): иконка, текст запроса голосом
/// персонала («Пациент просит рассмотреть: Достар Мед»), комментарий в кавычках и дата.
class SignalBanner extends StatelessWidget {
  const SignalBanner({super.key, required this.signal});

  final RouteSignal signal;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final comment = signal.comment?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 10),
      decoration: BoxDecoration(color: colors.surfaceSunken, borderRadius: BorderRadius.circular(AppRadius.plate)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(Icons.chat_bubble_outline, size: 18, color: colors.muted)),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: s.worklistSignal(signal.kind, name: shortOrgName(signal.toMoName ?? signal.toMoCode))),
                if (comment.isNotEmpty) TextSpan(text: ' — «$comment»'),
                TextSpan(text: ' · ${dateShort(signal.recordedAt)}', style: TextStyle(color: colors.muted)),
              ]),
              style: theme.textTheme.bodyMedium?.merge(AppType.numeric),
            ),
          ),
        ],
      ),
    );
  }
}

/// Последняя несостоявшаяся попытка перевода (веб `last-attempt`): «Последняя попытка: Перевод отменён: Достар Мед —
/// «причина» · дата». Незнакомый исход — «Перевод не состоялся».
class LastAttemptLine extends StatelessWidget {
  const LastAttemptLine({super.key, required this.attempt});

  final RouteTransferAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final colors = AppPalette.of(context);
    final reason = attempt.reason?.trim() ?? '';
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '${s.routeLastAttempt}: ', style: TextStyle(color: colors.muted)),
        TextSpan(text: s.routeAttemptText(attempt.outcome, RouteVoice.staff, name: shortOrgName(attempt.toMoName))),
        if (reason.isNotEmpty) TextSpan(text: ' — «$reason»'),
        if (attempt.at.isNotEmpty) TextSpan(text: ' · ${dateShort(attempt.at)}', style: TextStyle(color: colors.muted)),
      ]),
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.ink).merge(AppType.numeric),
    );
  }
}

/// Обязательное поле причины решения: подпись-кикер «… (обязательно)», многострочное поле и сообщение под ним —
/// своё («Укажите причину») или сервера (422).
class ReasonField extends StatelessWidget {
  const ReasonField({super.key, required this.label, required this.controller, this.hint, this.error, this.onChanged});

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? error;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FieldLabel(label),
          TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            onChanged: onChanged,
            decoration: InputDecoration(hintText: hint, errorText: error, errorMaxLines: 3),
          ),
        ],
      );
}

/// Подпись кнопки действия: пока запрос этого действия идёт — маленький индикатор перед текстом (текст остаётся,
/// кнопка не меняет ширину скачком и читается экранным диктором).
class BusyLabel extends StatelessWidget {
  const BusyLabel(this.text, {super.key, this.busy = false});

  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    if (!busy) {
      return Text(text, textAlign: TextAlign.center);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(width: AppSpacing.sm),
        Flexible(child: Text(text, textAlign: TextAlign.center)),
      ],
    );
  }
}
