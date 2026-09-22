import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Откуда число: прогноз модели, расчёт по формуле/справочнику или черновик языковой модели.
enum Origin { ml, formula, ai }

/// Метка происхождения — порт `OriginTag.vue`: та же конвенция «каждое число подписано». Тап открывает пояснение.
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
        borderRadius: BorderRadius.circular(AppRadius.pill),
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
                Text(note, style: Theme.of(sheet).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
          decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Text(
            label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: tone.fg, fontSize: 11, letterSpacing: 0.6, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }
}
