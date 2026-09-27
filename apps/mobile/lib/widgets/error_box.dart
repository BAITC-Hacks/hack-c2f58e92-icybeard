import 'package:flutter/material.dart';

import '../api/client.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Ошибка запроса прямо на экране (coral-wash, radius 16): problem+json как есть, остальное — «сервер недоступен»;
/// кнопка «Повторить». Никогда не показывает выдуманных чисел вместо данных.
class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, required this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error == null) {
      return const SizedBox.shrink();
    }
    final s = S.at(context);
    final tone = AppTones.of(context).danger;
    final text = error is ApiException ? error.toString() : s.serverUnavailable(error!);
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.sm, 14),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, color: tone.fg, size: 22),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 15, color: tone.fg))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: Text(s.retry)),
        ],
      ),
    );
  }
}
