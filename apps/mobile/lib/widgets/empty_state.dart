import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Панель состояния по доске W-States в белой карточке: иконка 48 в круге (по умолчанию inset/ink-2), заголовок
/// 17/500, одна фраза 14 ink-2, необязательное действие (малая кнопка или ссылка «→»). Основа для «пусто»,
/// «ничего не найдено», «ошибка», «нет прав», «данные устарели» (lib/widgets/state_view.dart).
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.title, this.body, this.icon = Icons.inbox_outlined, this.action, this.tone});

  final String title;
  final String? body;
  final IconData icon;
  final Widget? action;

  /// Цвет круга с иконкой; null — нейтральный (inset/ink-2).
  final Tone? tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final circle = tone ?? AppTones.of(context).neutral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.page, vertical: AppSpacing.xl),
      decoration: BoxDecoration(color: colors.card, borderRadius: BorderRadius.circular(AppRadius.card), boxShadow: colors.cardShadow),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Container(
              width: AppSizes.stateIcon,
              height: AppSizes.stateIcon,
              decoration: BoxDecoration(shape: BoxShape.circle, color: circle.bg),
              child: Icon(icon, size: 24, color: circle.fg),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
          if (body != null && body!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(body!, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: AppSpacing.md), action!],
        ],
      ),
    );
  }
}
