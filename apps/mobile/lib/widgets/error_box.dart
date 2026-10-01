import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import 'api_error.dart';
import 'state_view.dart';

/// Ошибка запроса прямо на экране (веб ErrorBox): плашка danger radius 14 с текстом из [apiErrorText] (409 —
/// «заголовок — пояснение» сервера, сбой сети и 5xx — «Сервер недоступен», без текста исключения) и «Повторить»,
/// если передан [onRetry]. Ответ 403 — состояние «Нет доступа». Никогда не показывает выдуманных чисел вместо данных.
class ErrorBox extends StatelessWidget {
  const ErrorBox({super.key, required this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final e = error;
    if (e == null) {
      return const SizedBox.shrink();
    }
    if (isForbidden(e)) {
      return ForbiddenState(error: e);
    }
    final s = S.at(context);
    final tone = AppTones.of(context).danger;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 14, AppSpacing.sm, 14),
        decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Row(
          children: [
            ExcludeSemantics(child: Icon(Icons.error_outline, color: tone.fg, size: 22)),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(apiErrorText(s, e), style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tone.fg))),
            if (onRetry != null) TextButton(onPressed: onRetry, child: Text(s.retry)),
          ],
        ),
      ),
    );
  }
}
