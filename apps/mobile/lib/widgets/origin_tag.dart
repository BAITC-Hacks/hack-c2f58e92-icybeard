import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import 'picker_sheet.dart';
import 'status_chip.dart';

/// Откуда число: прогноз модели, расчёт по правилу (формула, справочник, норматив) или черновик языковой модели.
enum Origin { ml, formula, ai }

/// Метка блока, у которого есть запасной расчёт: модель ответила — «прогноз модели», нет — «расчёт по правилу».
/// Так подписываются прогноз маршрута (`forecast.fromModel`), рабочий список (`modelBacked`), срок обеспечения
/// лекарства (`fillDaysP50Model != null`), прогноз ассистента направления и региональная оценка «Сколько ждут».
Origin originModelOrRule(bool fromModel) => fromModel ? Origin.ml : Origin.formula;

/// Метка блока без запасного расчёта: только когда числа дала модель, иначе метки нет. Так подписывается «Где
/// быстрее» (`alternativesModel != null`). Плитки KPI рабочего списка метки не несут — одна метка в шапке списка.
Origin? originModelOnly(bool fromModel) => fromModel ? Origin.ml : null;

/// Метка происхождения — та же конвенция, что в вебе: «каждое число подписано». Подпись строчными и без смены
/// регистра («прогноз модели», «расчёт по правилу», «черновик ИИ»); нейтральная пилюля surface-muted/text-secondary
/// для всех трёх видов. Тап открывает лист с пояснением (веб показывает его подсказкой). Внешний ориентир — не вид
/// происхождения: это фраза и свёрнутый «Источник» (`InlineDisclosure`), а чип — `StatusChip(tone: bench)`.
/// В строке рядом с другим текстом метку оборачивают во `Flexible`: казахские подписи длиннее.
class OriginTag extends StatelessWidget {
  const OriginTag(this.kind, {super.key, this.note});

  final Origin kind;

  /// Своё пояснение вместо стандартного (веб `originNote`).
  final String? note;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final tones = AppTones.of(context);
    final (tone, label, defaultNote) = switch (kind) {
      Origin.ml => (tones.ml, s.originMl, s.originMlNote),
      Origin.formula => (tones.formula, s.originFormula, s.originFormulaNote),
      Origin.ai => (tones.ai, s.originAi, s.originAiNote),
    };
    final text = note ?? defaultNote;
    return Semantics(
      button: true,
      label: '$label. $text',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () => showInfoSheet(context, title: label, body: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        child: ToneChip(label: label, fg: tone.fg, bg: tone.bg, radius: AppRadius.pill),
      ),
    );
  }
}
