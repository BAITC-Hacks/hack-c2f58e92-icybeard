import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'status_chip.dart';

/// Карточка записи скрайба по доске m-scribe-new: точка 10 px (danger-strong с ореолом danger-bg — идёт запись),
/// «Запись» 14/800, чип языка; таймер 40/800 табличными цифрами; волна — столбики 3 px accent на 40 px
/// (тишина — border-strong); строка согласия text-muted.
class ScribeRecordCard extends StatelessWidget {
  const ScribeRecordCard({super.key, required this.recording, required this.seconds, required this.levels, required this.language, required this.caption});

  final bool recording;
  final int seconds;

  /// Уровни 0…1 по столбикам, свежие справа.
  final List<double> levels;
  final String language;
  final String caption;

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
        crossAxisAlignment: CrossAxisAlignment.start,
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
              Expanded(child: Text(recording ? s.scribeRecordingTitle : s.scribeRecordShort, style: theme.textTheme.rowStrong)),
              StatusChip(language, tone: StatusTone.neutral),
            ],
          ),
          const SizedBox(height: 14),
          Text('$mm:$ss', style: theme.textTheme.displayMedium?.merge(AppType.numeric)),
          const SizedBox(height: 14),
          SizedBox(
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
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 14, color: colors.muted),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(caption, style: theme.textTheme.labelSmall?.copyWith(color: colors.muted))),
            ],
          ),
        ],
      ),
    );
  }
}
