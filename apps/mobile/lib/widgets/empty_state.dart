import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Панель состояния (веб StateBlock, доска W-States) в белой карточке: иконка в круге 48 (компактно — 40), заголовок
/// 16.5/800, одна фраза 13.5 text-secondary, необязательная вторая строка 12 (пояснение сервера) и действие (малая
/// кнопка или ссылка «→»). Круг по умолчанию нейтральный — surface-muted/text-secondary ([AppTones.quiet]);
/// warn — ошибка загрузки, info — данные устарели, danger — отказ. Основа для «пусто», «ничего не найдено»,
/// «ошибка», «нет доступа» (lib/widgets/state_view.dart).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.body, this.icon = Icons.inbox_outlined, this.action, this.tone, this.detail, this.compact = false});

  final String title;
  final String? body;
  final IconData icon;
  final Widget? action;

  /// Цвет круга с иконкой; null — нейтральный (surface-muted/text-secondary).
  final Tone? tone;

  /// Вторая строка мелко под [body] — например, пояснение сервера к ошибке.
  final String? detail;

  /// Компактный вариант внутри карточки или списка: круг 40, меньше отступы.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final circle = tone ?? AppTones.of(context).quiet;
    final size = compact ? AppSizes.iconButton : AppSizes.stateIcon;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? AppSpacing.md : AppSpacing.page, vertical: compact ? AppSpacing.lg : AppSpacing.xl),
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(AppRadius.card), boxShadow: colors.cardShadow),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(shape: BoxShape.circle, color: circle.bg),
              child: Icon(icon, size: compact ? 20 : 24, color: circle.fg),
            ),
          ),
          SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (body != null && body!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(body!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
          if (detail != null && detail!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(detail!, style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: AppSpacing.md), action!],
        ],
      ),
    );
  }
}
