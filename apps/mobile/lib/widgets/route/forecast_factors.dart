import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';

/// Направление вклада фактора в ожидание: добавляет дни, убавляет или почти не влияет (меньше половины дня).
enum FactorDirection { plus, minus, zero }

/// Строка блока «Из чего сложился прогноз» простыми словами: [label] — подпись признака, [hint] — пояснение по
/// знаку вклада (пустая строка — пояснения нет), [effect] — вклад целыми днями, [direction] — цвет вклада.
/// [name] — код признака модели (`Factor.name`), по нему экран может переписать подпись через [copyWith].
@immutable
class ForecastFactorView {
  const ForecastFactorView({required this.name, required this.label, required this.hint, required this.effect, required this.direction});

  final String name;
  final String label;
  final String hint;
  final String effect;
  final FactorDirection direction;

  /// Новая строка с другой подписью или пояснением (ассистент направления заменяет same_mo, когда направляющая
  /// организация не указана); исходная строка не меняется.
  ForecastFactorView copyWith({String? label, String? hint}) =>
      ForecastFactorView(name: name, label: label ?? this.label, hint: hint ?? this.hint, effect: effect, direction: direction);
}

/// Хвост текста модели в скобках: «очередь …: 133 (+9.0 дн.)» → «очередь …: 133».
final _trailingParens = RegExp(r'\s*\([^)]*\)\s*$');

/// Факторы модели ([Factor] из `shap.factors` маршрута или `explanation.factors` прогноза) → строки для показа, в том
/// же порядке. Правила — useForecastFactors.ts веба:
/// - текст модели без хвоста в скобках, значение — после первого «: »;
/// - same_mo: «Направляет эта же больница», если значение True или 1, иначе «Направляет другая организация»;
///   queue_len со значением — «Длина очереди: N»; profile_code при [profileName] — «Профиль койки: …»;
///   иначе подпись словаря по коду, незнакомый код — текст модели;
/// - вклад: округлённый модуль в днях; 0 — «почти не влияет» без пояснения, иначе «+N дн. к ожиданию» /
///   «−N дн. от ожидания» и пояснение по знаку (same_mo — по значению). Нечисловой вклад считается нулевым.
/// Чистая функция: вход не меняется, результат — новый список.
List<ForecastFactorView> forecastFactors(List<Factor> factors, S s, {String? profileName}) =>
    [for (final factor in factors) _view(factor, s, profileName)];

ForecastFactorView _view(Factor factor, S s, String? profileName) {
  final raw = factor.text.replaceFirst(_trailingParens, '');
  final colon = raw.indexOf(': ');
  final value = colon >= 0 ? raw.substring(colon + 2).trim() : '';
  final sameOrganization = value == 'True' || value == '1';
  final label = switch (factor.name) {
    'same_mo' => s.factorSameMo(sameOrganization),
    'queue_len' when value.isNotEmpty => s.factorQueueLength(value),
    'profile_code' when profileName != null && profileName.isNotEmpty => s.factorProfileNamed(profileName),
    _ => s.factorLabel(factor.name) ?? raw,
  };
  final contribution = factor.contribution.isFinite ? factor.contribution : 0.0;
  final amount = contribution.abs().round();
  final direction = amount == 0
      ? FactorDirection.zero
      : contribution > 0
          ? FactorDirection.plus
          : FactorDirection.minus;
  final effect = switch (direction) {
    FactorDirection.zero => s.factorNoEffect,
    FactorDirection.plus => s.factorAddsDays(amount),
    FactorDirection.minus => s.factorTakesDays(amount),
  };
  final hintKey = factor.name == 'same_mo' ? (sameOrganization ? 'same_mo_yes' : 'same_mo_no') : factor.name;
  final hint = direction == FactorDirection.zero ? '' : s.factorHint(hintKey, plus: direction == FactorDirection.plus) ?? '';
  return ForecastFactorView(name: factor.name, label: label, hint: hint, effect: effect, direction: direction);
}

/// Список факторов прогноза: необязательный вводный абзац [lead] (`factorsLead`), строки «подпись | вклад» с
/// пояснением на всю ширину под ними и необязательная заметка [note] (`factorsNote`). Вклад справа жирным,
/// табличными цифрами: добавляет дни — danger, убавляет — ok, почти не влияет — приглушённый; его ширина ограничена
/// 2/5 строки — длинная фраза переносится, а не переполняет строку (на телефоне пояснение не сжимается в узкую
/// колонку, как было бы в двухколоночной строке веба). Заголовок и раскрытие («Из чего сложился прогноз») — у
/// экрана. Пустой список — ничего.
class ForecastFactorList extends StatelessWidget {
  const ForecastFactorList({super.key, required this.items, this.lead, this.note});

  final List<ForecastFactorView> items;
  final String? lead;
  final String? note;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: colors.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lead != null && lead!.isNotEmpty) ...[Text(lead!, style: muted), const SizedBox(height: AppSpacing.xs)],
        for (final (i, item) in items.indexed) _FactorRow(item: item, first: i == 0),
        if (note != null && note!.isNotEmpty) ...[const SizedBox(height: AppSpacing.sm), Text(note!, style: muted)],
      ],
    );
  }
}

class _FactorRow extends StatelessWidget {
  const _FactorRow({required this.item, required this.first});

  final ForecastFactorView item;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final tones = AppTones.of(context);
    final effectColor = switch (item.direction) {
      FactorDirection.plus => tones.danger.fg,
      FactorDirection.minus => tones.ok.fg,
      FactorDirection.zero => colors.muted,
    };
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: first ? null : BoxDecoration(border: Border(top: BorderSide(color: colors.borderSoft))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: Text(item.label, style: theme.textTheme.bodyMedium)),
                const SizedBox(width: AppSpacing.md),
                Flexible(
                  flex: 2,
                  child: Text(
                    item.effect,
                    textAlign: TextAlign.end,
                    style: theme.textTheme.row.copyWith(fontWeight: FontWeight.w700, color: effectColor).merge(AppType.numeric),
                  ),
                ),
              ],
            ),
            if (item.hint.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 2), child: Text(item.hint, style: theme.textTheme.rowDetail.copyWith(color: colors.muted))),
          ],
        ),
      ),
    );
  }
}
