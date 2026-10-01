import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'status_chip.dart';

/// Карточка записи приёма во время сессии (веб: карточка «Запись» скрайба): точка 10 px (danger-strong с ореолом
/// danger-soft — идёт запись), «Запись», чип языка приёма; таймер мм:сс 40/800 табличными цифрами (красный во время
/// записи); волна уровней микрофона — столбики accent, только пока идёт запись; заметка о модели распознавания;
/// кнопки «Записать с микрофона» / «Остановить» и «Вставить текст» во всю ширину; внизу — предупреждение «Отмена
/// удалит аудио и текст…» и «Отменить запись» (неактивна во время записи). null у колбэка — кнопка неактивна.
class ScribeRecordCard extends StatelessWidget {
  const ScribeRecordCard({
    super.key,
    required this.recording,
    required this.seconds,
    required this.levels,
    required this.language,
    this.note,
    this.onRecord,
    required this.onStop,
    this.onPaste,
    this.onDiscard,
  });

  final bool recording;
  final int seconds;

  /// Уровни 0…1 по столбикам, свежие справа.
  final List<double> levels;

  /// Подпись языка приёма («Русский» / «Қазақша»).
  final String language;

  /// Заметка о модели распознавания (скачивается, загружается, недоступна, заглушка); null — без заметки.
  final String? note;
  final VoidCallback? onRecord;
  final VoidCallback onStop;
  final VoidCallback? onPaste;
  final VoidCallback? onDiscard;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final mm = (seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (seconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.page, AppSpacing.lg, AppSpacing.lg),
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(AppRadius.card), boxShadow: colors.cardShadow),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: recording ? colors.dangerStrong : colors.faint,
                  boxShadow: recording ? [BoxShadow(color: colors.dangerSoft, spreadRadius: 4)] : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(s.scribeRecordShort, style: theme.textTheme.rowStrong)),
              StatusChip(language, tone: StatusTone.neutral),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Semantics(
            liveRegion: recording,
            child: Text('$mm:$ss', style: theme.textTheme.displayMedium?.copyWith(color: recording ? colors.dangerStrong : null).merge(AppType.numeric)),
          ),
          if (recording) ...[const SizedBox(height: AppSpacing.md), _Levels(levels: levels)],
          if (note != null) ...[const SizedBox(height: AppSpacing.md), _Note(note!)],
          const SizedBox(height: AppSpacing.md),
          if (recording)
            FilledButton.icon(onPressed: onStop, icon: const Icon(Icons.stop, size: 20), label: Text(s.scribeStopButton))
          else
            FilledButton.icon(onPressed: onRecord, icon: const Icon(Icons.mic, size: 20), label: Text(s.aiScribeRecordMic)),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(onPressed: recording ? null : onPaste, icon: const Icon(Icons.content_paste, size: 20), label: Text(s.aiScribePasteText)),
          const SizedBox(height: AppSpacing.md),
          Divider(height: 1, color: colors.borderSoft),
          const SizedBox(height: AppSpacing.md),
          Text(s.aiScribeDiscardHint, style: theme.textTheme.labelSmall),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            style: AppButtons.danger(context),
            onPressed: recording ? null : onDiscard,
            icon: const Icon(Icons.delete_outline, size: 20),
            label: Text(s.aiScribeDiscard),
          ),
        ],
      ),
    );
  }
}

/// Волна уровня микрофона: столбики 3 px accent высотой 8…38 на 40 px; тишина — приглушённые.
class _Levels extends StatelessWidget {
  const _Levels({required this.levels});

  final List<double> levels;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: 40,
        child: Row(
          children: [
            for (final level in levels)
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: AnimatedContainer(
                  duration: AppDurations.fast,
                  width: AppSizes.bar,
                  height: 8 + 30 * level,
                  decoration: BoxDecoration(color: level > 0 ? colors.accent : colors.faint, borderRadius: BorderRadius.circular(2)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Заметка о модели распознавания с иконкой «i» (веб `.model-note`).
class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 18, color: colors.muted),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
      ],
    );
  }
}
