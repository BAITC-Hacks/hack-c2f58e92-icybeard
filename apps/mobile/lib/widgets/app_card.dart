import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';

/// Белая карточка radius 18 с мягкой тенью `--shadow-card` (доски m-*): `padding 20 16 16` у hero-карточек,
/// `16` у списков и опций, `4 16` у карточек-списков (строки со своими отступами). Тап — по всей карточке.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = hero, this.onTap, this.color, this.border, this.semanticsLabel});

  static const hero = EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.page, AppSpacing.lg, AppSpacing.lg);
  static const plain = EdgeInsets.all(AppSpacing.lg);
  static const list = EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs);

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  /// Inset-обводка 2 px accent у выбранной опции-карточки.
  final BoxBorder? border;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final radius = BorderRadius.circular(AppRadius.card);
    final body = Container(
      padding: padding,
      decoration: BoxDecoration(color: color ?? colors.card, borderRadius: radius, border: border, boxShadow: colors.cardShadow),
      child: child,
    );
    if (onTap == null) {
      return body;
    }
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: Material(
        color: ColorTokens.transparent,
        child: InkWell(borderRadius: radius, onTap: onTap, child: body),
      ),
    );
  }
}

/// Label над блоком внутри карточки: uppercase 12/500 ink-2 слева, чип справа.
class CardLabel extends StatelessWidget {
  const CardLabel(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Row(
      children: [
        Expanded(child: Text(text.toUpperCase(), style: theme.textTheme.overline.copyWith(color: colors.muted), maxLines: 2, overflow: TextOverflow.ellipsis)),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

/// Строка списка внутри карточки: min-height 56, `padding 12 0`, hairline снизу кроме последней; слева
/// необязательная точка 6 px (accent — новое) или иконка, справа значение 12–14 ink-2 и шеврон при действии.
class ListRow extends StatelessWidget {
  const ListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.last = false,
    this.strong = false,
    this.dot,
    this.titleColor,
    this.chevron = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool last;

  /// Заголовок 15/500 вместо 15/400.
  final bool strong;

  /// true — синяя точка (новое), false — пустое место под точку, null — без колонки.
  final bool? dot;
  final Color? titleColor;

  /// Шеврон справа при наличии действия (false — когда справа своя иконка, как у «Выйти»).
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final row = Container(
      constraints: const BoxConstraints(minHeight: AppSizes.row),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: last ? null : BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
      child: Row(
        children: [
          if (dot != null) ...[
            Container(
              width: AppSizes.dot,
              height: AppSizes.dot,
              decoration: BoxDecoration(shape: BoxShape.circle, color: dot! ? colors.accent : ColorTokens.transparent),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          if (leading != null) ...[leading!, const SizedBox(width: AppSpacing.md)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: (strong ? theme.textTheme.rowStrong : theme.textTheme.row).copyWith(color: titleColor),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!, style: theme.textTheme.rowDetail.copyWith(color: colors.muted).merge(AppType.numeric), maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: AppSpacing.md), trailing!],
          if (onTap != null && chevron) ...[const SizedBox(width: AppSpacing.xs), Icon(Icons.chevron_right, size: 20, color: colors.muted)],
        ],
      ),
    );
    if (onTap == null) {
      return row;
    }
    return Semantics(button: true, child: InkWell(onTap: onTap, child: row));
  }
}

/// Значение справа в строке списка: 14 ink-2 (500 — акцент), табличные цифры.
class RowValue extends StatelessWidget {
  const RowValue(this.text, {super.key, this.strong = false, this.color, this.size = 14});

  final String text;
  final bool strong;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(fontSize: size, color: color ?? (strong ? colors.ink : colors.muted), fontWeight: strong ? FontWeight.w500 : FontWeight.w400)
          .merge(AppType.numeric),
      textAlign: TextAlign.end,
    );
  }
}

/// Ссылка-действие 13.5/700 цвета `--link` со стрелкой «→» (ghost-ссылка components.md).
class ArrowLink extends StatelessWidget {
  const ArrowLink(this.text, {super.key, this.onTap});

  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(child: Text(text, style: theme.textTheme.titleSmall?.copyWith(color: colors.link), maxLines: 1, overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 6),
        Text('→', style: theme.textTheme.titleSmall?.copyWith(color: colors.link)),
      ],
    );
    if (onTap == null) {
      return child;
    }
    return InkWell(borderRadius: BorderRadius.circular(AppRadius.sm), onTap: onTap, child: Padding(padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs), child: child));
  }
}

/// Label над полем ввода: uppercase 12/500 ink-2.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text.toUpperCase(), style: Theme.of(context).textTheme.overline.copyWith(color: AppPalette.of(context).muted)),
      );
}
