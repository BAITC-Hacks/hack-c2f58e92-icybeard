import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Карточка-сигнал гражданина на accent-soft (веб `signal-card` RouteCitizenView.vue, доска m-home-new): иконка 22
/// и жирный заголовок, под ними строки текста ([lines] — основной текст и приглушённые пояснения, стиль задаёт
/// вызывающий), затем кнопки действий друг под другом во всю ширину ([actions]) — на телефоне главная кнопка не
/// уходит за край при крупном шрифте. Несёт состояние маршрута, ответ врача и запрос записи приёма.
class SignalCard extends StatelessWidget {
  const SignalCard({super.key, required this.title, this.icon = Icons.verified_user_outlined, this.lines = const [], this.actions = const []});

  final String title;
  final IconData icon;
  final List<Widget> lines;
  final List<Widget> actions;

  /// 16 по бокам и снизу, 14 сверху.
  static const _padding = EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, AppSpacing.lg);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Container(
      padding: _padding,
      decoration: BoxDecoration(color: colors.accentSoft, borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ExcludeSemantics(child: Icon(icon, size: 22, color: colors.accentHover)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: Semantics(header: true, child: Text(title, style: theme.textTheme.titleMedium))),
            ],
          ),
          for (final line in lines) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: line),
          if (actions.isNotEmpty) const SizedBox(height: AppSpacing.xs),
          for (final action in actions) Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: action),
        ],
      ),
    );
  }
}
