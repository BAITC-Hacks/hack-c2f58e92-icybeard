import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import 'format.dart';
import 'picker_sheet.dart';

/// Короткое имя организации в тексте ([shortOrgName]); тап открывает лист с полным юридическим именем. Если
/// сокращать нечего — обычный текст без действия. Стиль по умолчанию — `bodySmall` (13.5 text-secondary).
class OrgName extends StatelessWidget {
  const OrgName(this.name, {super.key, this.style, this.maxLines = 1, this.prefix = '', this.suffix = ''});

  final String name;
  final TextStyle? style;
  final int maxLines;

  /// Текст до и после имени в той же строке («Хирургия · », « ≈ 7 дн.»).
  final String prefix;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final short = shortOrgName(name);
    final base = style ?? Theme.of(context).textTheme.bodySmall;
    if (short == name.trim()) {
      return Text('$prefix$short$suffix', style: base, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    }
    final colors = AppPalette.of(context);
    return Semantics(
      button: true,
      label: '$prefix$short$suffix. ${S.at(context).fullNameHint}',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => showOrgNameSheet(context, name),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: prefix),
              TextSpan(
                text: short,
                style: TextStyle(decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted, decorationColor: colors.faint),
              ),
              TextSpan(text: suffix),
            ],
          ),
          style: base,
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Лист с полным юридическим именем организации: заголовок — короткое имя ([SheetHeader]), ниже подпись
/// «Полное юридическое название» и само имя с возможностью выделить и скопировать.
Future<void> showOrgNameSheet(BuildContext context, String name) {
  final theme = Theme.of(context);
  return showInfoSheet(
    context,
    title: shortOrgName(name),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(S.at(context).fullNameLabel, style: theme.textTheme.labelSmall),
        const SizedBox(height: AppSpacing.xs),
        SelectableText(name, style: theme.textTheme.bodyMedium),
      ],
    ),
  );
}
