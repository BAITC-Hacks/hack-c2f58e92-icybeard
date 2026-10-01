import 'package:flutter/material.dart';

import '../api/client.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'api_error.dart' as api_error;
import 'empty_state.dart';
import 'format.dart';

/// Общие состояния списков и сводок (веб `components/states/*`, доска W-States; загрузка — скелетоны
/// `skeleton.dart`, пусто — [EmptyState]): ошибка загрузки с «Повторить», нет доступа, ничего не найдено по
/// фильтру, данные устарели. Ответ API 403 всегда рисуется как «Нет доступа» — проверки на клиенте только UX,
/// источник истины — API (docs/rbac.md). Тексты — веб `states.*` и `access.*`.

/// true — ответ API 403 (нет разрешения, чужая организация, нет привязки к организации).
bool isForbidden(Object? error) => error is ApiException && error.isForbidden;

/// Ошибка загрузки (веб StateError): янтарный круг, «Не удалось загрузить данные», фраза по коду — «Сервер не
/// отвечает — проверьте соединение.» (сбой сети), «Раздел ещё не подключён на сервере (код 404).», иначе «Сервер
/// ответил ошибкой. Код N.»; пояснение сервера — второй строкой; «Повторить», если передан [onRetry]. 403 —
/// [ForbiddenState].
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry, this.compact = false});

  final Object error;
  final VoidCallback? onRetry;

  /// Компактный вариант внутри карточки.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (isForbidden(error)) {
      return ForbiddenState(error: error, compact: compact);
    }
    final s = S.at(context);
    final e = error;
    final (body, detail) = switch (e) {
      ApiException(status: 404) => (s.loadErrorNotConnected, api_error.humanDetail(e) ?? api_error.humanTitle(e)),
      ApiException() => (s.loadErrorCode(e.status), api_error.humanDetail(e) ?? api_error.humanTitle(e)),
      _ => (s.loadErrorNetwork, null),
    };
    return EmptyState(
      icon: Icons.warning_amber_rounded,
      tone: AppTones.of(context).warn,
      title: s.loadErrorTitle,
      body: body,
      detail: detail,
      compact: compact,
      action: onRetry == null ? null : OutlinedButton(style: AppButtons.small(context), onPressed: onRetry, child: Text(s.retry)),
    );
  }
}

/// Нет доступа (веб StateNoAccess): замок в нейтральном круге, «Нет доступа к разделу» и причина — фраза для кодов
/// `no_organization` / `other_organization`, понятный заголовок и пояснение сервера как есть, иначе «Доступ выдаёт
/// администратор организации.».
class ForbiddenState extends StatelessWidget {
  const ForbiddenState({super.key, this.error, this.body, this.compact = false});

  final Object? error;

  /// Своя причина вместо разбора ответа API.
  final String? body;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return EmptyState(icon: Icons.lock_outline, title: s.noAccessTitle, body: body ?? forbiddenReason(s, error), compact: compact);
  }

  /// Причина отказа для текста под заголовком; без причины — общий текст. Разбор — `forbiddenReason` из
  /// lib/widgets/api_error.dart.
  static String forbiddenReason(S s, Object? error) => api_error.forbiddenReason(s, error) ?? s.noAccessGeneric;
}

/// Фильтр ничего не нашёл (веб StateFiltered): лупа, «Ничего не найдено», «Попробуйте снять часть фильтров» и
/// «Сбросить фильтры».
class FilteredEmptyState extends StatelessWidget {
  const FilteredEmptyState({super.key, this.body, this.onReset, this.resetLabel});

  final String? body;
  final VoidCallback? onReset;
  final String? resetLabel;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return EmptyState(
      icon: Icons.search_off,
      title: s.pickerNothingFound,
      body: body ?? s.filteredBody,
      action: onReset == null ? null : OutlinedButton(style: AppButtons.small(context), onPressed: onReset, child: Text(resetLabel ?? s.filteredReset)),
    );
  }
}

/// Данные устарели (веб StateStale): баннер над списком на accent-subtle radius 12 без тени — часы в круге 28
/// accent-soft/accent-strong, жирное «Данные на дд.мм.гггг» и « · следующая загрузка — дд.мм.гггг», если известна.
/// Кнопки «Обновить» нет: данные обновляет загрузка витрин, а не пользователь (pull-to-refresh экрана остаётся).
/// Показывается, когда срез старше [maxAge] ([isStale]).
class StaleDataBanner extends StatelessWidget {
  const StaleDataBanner({super.key, required this.asOf, this.next});

  /// Дата среза данных (ISO).
  final String asOf;

  /// Дата следующей загрузки (ISO), если известна.
  final String? next;

  static const maxAge = Duration(days: 7);

  /// true — срез данных старше [maxAge] относительно [now].
  static bool isStale(String? asOf, {DateTime? now}) {
    final day = localDay(asOf);
    return day != null && (now ?? DateTime.now()).difference(day) > maxAge;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final tone = AppTones.of(context).info;
    final upcoming = next;
    return Semantics(
      container: true,
      child: Container(
        key: const ValueKey('stale-banner'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(color: colors.accentSubtle, borderRadius: BorderRadius.circular(AppRadius.md)),
        child: Row(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(shape: BoxShape.circle, color: tone.bg),
                child: Icon(Icons.schedule, size: 16, color: tone.fg),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: s.staleAsOf(dateShort(asOf)), style: const TextStyle(fontWeight: FontWeight.w700)),
                  if (upcoming != null && upcoming.isNotEmpty) TextSpan(text: ' · ${s.staleNext(dateShort(upcoming))}'),
                ]),
                style: theme.textTheme.bodySmall?.copyWith(color: colors.ink).merge(AppType.numeric),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
