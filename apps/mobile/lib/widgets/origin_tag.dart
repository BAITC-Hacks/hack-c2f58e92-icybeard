import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import 'status_chip.dart';

/// Откуда число: прогноз модели, расчёт по формуле/справочнику или черновик языковой модели.
enum Origin { ml, formula, ai }

/// Метка происхождения — та же конвенция, что в вебе: «каждое число подписано». Чип radius 8 («ML-модель» —
/// heal-wash/ink, «формула» — soft/ink-2, «AI» — coral-wash/ink); тап открывает пояснение.
class OriginTag extends StatelessWidget {
  const OriginTag(this.kind, {super.key});

  final Origin kind;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final tones = AppTones.of(context);
    final (tone, label, note) = switch (kind) {
      Origin.ml => (tones.ml, s.originMl, s.originMlNote),
      Origin.formula => (tones.formula, s.originFormula, s.originFormulaNote),
      Origin.ai => (tones.ai, s.originAi, s.originAiNote),
    };
    return Semantics(
      button: true,
      label: '$label. $note',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          builder: (sheet) => Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(sheet).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(note, style: Theme.of(sheet).textTheme.bodySmall),
              ],
            ),
          ),
        ),
        child: ToneChip(label: label, fg: tone.fg, bg: tone.bg),
      ),
    );
  }
}
