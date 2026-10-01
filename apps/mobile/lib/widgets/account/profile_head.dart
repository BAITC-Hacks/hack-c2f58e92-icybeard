import 'package:flutter/material.dart';

import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../origin_tag.dart';
import '../picker_sheet.dart';

/// Шапка профиля (веб `ProfileView.vue`, карточка «кто я»): круг с инициалами, имя, роль (у сотрудника — с короткой
/// больницей и кодом), ИИН только маской и строка о недоступном входе через eGov mobile. Без своей карточки —
/// кладётся в карточку профиля над строками.
class ProfileHead extends StatelessWidget {
  const ProfileHead({super.key, required this.name, required this.roleLine, this.iinMasked, this.egovOff = false});

  final String name;
  final String roleLine;

  /// ИИН маской, как его отдаёт API; null — у учётной записи ИИН нет.
  final String? iinMasked;

  /// Вход через eGov mobile сейчас недоступен — строка веба `account.profile.egovOff`.
  final bool egovOff;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Container(
            width: AppSizes.control,
            height: AppSizes.control,
            alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colors.accentSoft),
            child: Text(initialsOf(name), style: theme.textTheme.titleSmall?.copyWith(color: colors.accentHover)),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.titleLarge),
              const SizedBox(height: 2),
              Text(roleLine, style: theme.textTheme.bodySmall),
              if (iinMasked != null) Text('${s.iinLabel}: $iinMasked', style: theme.textTheme.bodySmall?.merge(AppType.numeric)),
              if (egovOff) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(s.egovOffLine, style: theme.textTheme.labelSmall),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Инициалы для круга: первые буквы двух первых слов имени (веб `initials`); пустое имя — «?».
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2);
  final letters = words.map((w) => w.characters.first.toUpperCase()).join();
  return letters.isEmpty ? '?' : letters;
}

/// Лист «Откуда берутся цифры» (веб `welcome.forecastTitle` … `howNote`, P-7): две метки происхождения — «прогноз
/// модели» и «расчёт по правилу» — с пояснениями и заметка, что прогноз — оценка, решение принимает врач.
Future<void> showForecastsSheet(BuildContext context) {
  final s = S.at(context);
  final theme = Theme.of(context);
  Widget tagged(Origin origin, String text) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [OriginTag(origin), const SizedBox(width: AppSpacing.md), Expanded(child: Text(text, style: theme.textTheme.bodyMedium))],
        ),
      );
  return showInfoSheet(
    context,
    title: s.forecastsTitle,
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.forecastsIntro, style: theme.textTheme.bodyMedium?.copyWith(height: 1.5)),
        const SizedBox(height: AppSpacing.lg),
        tagged(Origin.ml, s.forecastsMl),
        tagged(Origin.formula, s.forecastsFormula),
        const SizedBox(height: AppSpacing.xs),
        Text(s.forecastsNote, style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
      ],
    ),
  );
}
