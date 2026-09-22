import 'package:flutter/material.dart';

import '../api/client.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';

/// Ошибка запроса прямо на экране: problem+json как есть, остальное — «сервер недоступен»; кнопка «Повторить».
/// Никогда не показывает выдуманных чисел вместо данных.
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: tone.fg, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tone.fg))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: Text(s.retry)),
        ],
      ),
    );
  }
}
