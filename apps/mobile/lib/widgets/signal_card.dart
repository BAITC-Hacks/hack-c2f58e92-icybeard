import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Карточка-сигнал на accent-soft по доске m-home-new («Врач предложил …», «Пациент просит …»): radius 18,
/// `padding 14 16`, иконка 22, две строки и стрелка «→» accent-strong, если есть действие.
class SignalCard extends StatelessWidget {
  const SignalCard({super.key, required this.title, this.subtitle, this.icon = Icons.verified_user_outlined, this.onTap});

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final radius = BorderRadius.circular(AppRadius.card);
    final body = Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.lg, 14),
      decoration: BoxDecoration(color: colors.accentSoft, borderRadius: radius),
      child: Row(
        children: [
          Icon(icon, size: 22, color: colors.accentHover),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppSpacing.md),
            Text('→', style: theme.textTheme.titleSmall?.copyWith(color: colors.accentHover)),
          ],
        ],
      ),
    );
    if (onTap == null) {
      return body;
    }
    return Semantics(
      button: true,
      child: Material(color: ColorTokens.transparent, child: InkWell(borderRadius: radius, onTap: onTap, child: body)),
    );
  }
}
