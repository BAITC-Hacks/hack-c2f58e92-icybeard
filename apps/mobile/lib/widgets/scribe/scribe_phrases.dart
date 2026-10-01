import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../status_chip.dart';
import 'scribe_text.dart';

/// Карточка «Стенограмма» (веб: список фраз скрайба): фраза — строка с меткой «мм:сс–мм:сс · RU|KK» и пометкой, кто
/// исправил; тап по фразе открывает правку в листе ([onEdit]); у исправленной фразы — серый блок «Исходный текст
/// распознавания» с «вернуть» ([onRevert]). Под списком — подсказка и «Исправить термины (ИИ)» ([onCorrect]). Пусто —
/// «Распознаём речь…» во время обработки, иначе «Стенограммы пока нет…». [locked] — правка недоступна (идёт запись
/// или обработка).
class ScribePhrasesCard extends StatelessWidget {
  const ScribePhrasesCard({
    super.key,
    required this.segments,
    required this.locked,
    required this.processing,
    required this.correcting,
    this.savingIndex,
    required this.onEdit,
    required this.onRevert,
    required this.onCorrect,
  });

  final List<TranscriptSegment> segments;
  final bool locked;
  final bool processing;
  final bool correcting;
  final int? savingIndex;
  final void Function(int index) onEdit;
  final void Function(int index) onRevert;
  final VoidCallback onCorrect;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.scribeTranscriptTitle),
          const SizedBox(height: AppSpacing.sm),
          if (segments.isEmpty)
            Row(
              children: [
                if (processing) ...[const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: AppSpacing.sm)],
                Expanded(child: Text(processing ? s.aiScribeTranscribing : s.aiScribeNoTranscript, style: theme.textTheme.bodySmall)),
              ],
            )
          else ...[
            for (final (i, segment) in segments.indexed)
              _PhraseRow(
                segment: segment,
                saving: savingIndex == i,
                onTap: locked ? null : () => onEdit(i),
                onRevert: locked ? null : () => onRevert(i),
                last: i == segments.length - 1,
              ),
            if (!locked) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(s.aiScribeEditHint, style: theme.textTheme.labelSmall),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: correcting ? null : onCorrect,
                icon: correcting ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_fix_high, size: 20),
                label: Text(s.aiScribeCorrectTerms),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PhraseRow extends StatelessWidget {
  const _PhraseRow({required this.segment, required this.saving, required this.onTap, required this.onRevert, required this.last});

  final TranscriptSegment segment;
  final bool saving;
  final VoidCallback? onTap;
  final VoidCallback? onRevert;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final fixedBy = s.aiScribeFixedBy(segment.source);
    final original = segment.original;
    return Container(
      decoration: last ? null : BoxDecoration(border: Border(bottom: BorderSide(color: colors.borderSoft))),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: onTap != null,
            hint: onTap == null ? null : s.aiScribeEditHint,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: AppSizes.compact),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${scribeStamp(segment.t0, segment.t1)} · ${scribeSegmentLanguage(segment.text).toUpperCase()}',
                          style: theme.textTheme.labelSmall?.copyWith(color: colors.textFaint).merge(AppType.numeric),
                        ),
                        if (fixedBy.isNotEmpty) StatusChip(fixedBy, tone: segment.source == 'ai' ? StatusTone.accent : StatusTone.neutral),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(segment.text, style: theme.textTheme.bodyMedium)),
                        if (onTap != null) ...[const SizedBox(width: AppSpacing.sm), Icon(Icons.edit_outlined, size: 18, color: colors.textFaint)],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (saving) const Padding(padding: EdgeInsets.only(top: AppSpacing.xs), child: LinearProgressIndicator(minHeight: 2)),
          if (original != null) ...[const SizedBox(height: AppSpacing.sm), _Original(text: original, onRevert: onRevert)],
        ],
      ),
    );
  }
}

/// Исходный текст распознавания под исправленной фразой и «вернуть» (сохранить исходный текст — правка снимается).
class _Original extends StatelessWidget {
  const _Original({required this.text, required this.onRevert});

  final String text;
  final VoidCallback? onRevert;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, AppSpacing.md),
      decoration: BoxDecoration(color: colors.neutralSoft, borderRadius: BorderRadius.circular(AppRadius.plate), border: Border.all(color: colors.borderSoft)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(s.aiScribeWasText.toUpperCase(), style: theme.textTheme.overline.copyWith(color: colors.muted))),
              if (onRevert != null) TextButton.icon(onPressed: onRevert, icon: const Icon(Icons.undo, size: 18), label: Text(s.aiScribeRevert)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.sm),
            child: Text(text, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
