import 'package:flutter/material.dart';

import '../api/client.dart';
import '../l10n/strings.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'app_card.dart';
import 'empty_state.dart';
import 'format.dart';

/// Общие состояния списков и сводок по доске W-States (загрузка — скелетоны `skeleton.dart`, пусто — [EmptyState]):
/// ошибка с «Повторить», нет прав, ничего не найдено по фильтру, данные устарели. Ответ API 403 всегда рисуется как
/// «Нет доступа» — проверки на клиенте только UX, источник истины — API (docs/rbac.md).

/// true — ответ API 403 (нет разрешения, чужая организация, нет привязки к организации).
bool isForbidden(Object? error) => error is ApiException && error.status == 403;

/// Ошибка загрузки: иконка в янтарном круге, «Не удалось загрузить данные», причина и код, «Повторить».
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (isForbidden(error)) {
      return ForbiddenState(error: error);
    }
    final s = S.at(context);
    final e = error;
    final body = e is ApiException ? s.stateErrorCode(e.detail ?? e.title, e.status) : s.stateNetworkBody;
    return EmptyState(
      icon: Icons.warning_amber_rounded,
      tone: AppTones.of(context).warn,
      title: s.stateErrorTitle,
      body: body,
      action: onRetry == null ? null : OutlinedButton(style: AppButtons.small(context), onPressed: onRetry, child: Text(s.retry)),
    );
  }
}

/// Нет прав: замок в нейтральном круге, «Раздел недоступен для вашей роли» и причина из problem+json.
class ForbiddenState extends StatelessWidget {
  const ForbiddenState({super.key, this.error, this.body});

  final Object? error;

  /// Своя причина вместо разбора ответа API.
  final String? body;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return EmptyState(icon: Icons.lock_outline, title: s.stateForbiddenTitle, body: body ?? forbiddenReason(s, error));
  }

  /// Причина отказа: коды `no_organization` / `other_organization` из docs/rbac.md, осмысленный заголовок API
  /// («Пациент другого региона») как есть, иначе — «доступ выдаёт администратор».
  static String forbiddenReason(S s, Object? error) {
    if (error is! ApiException) {
      return s.stateForbiddenBody;
    }
    return switch (error.detail) {
      'no_organization' => s.stateNoOrganization,
      'other_organization' => s.stateOtherOrganization,
      _ => error.title.startsWith('HTTP ') || error.title == 'Forbidden' ? s.stateForbiddenBody : error.title,
    };
  }
}

/// Фильтр ничего не нашёл: лупа, «Ничего не найдено», подсказка и «Сбросить фильтры».
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
      body: body ?? s.stateFilterBody,
      action: onReset == null ? null : OutlinedButton(style: AppButtons.small(context), onPressed: onReset, child: Text(resetLabel ?? s.resetFilters)),
    );
  }
}

/// Данные устарели: компактная строка над списком — часы в info-круге, «Данные на дд.мм.гггг», пояснение и
/// «Обновить →». Показывается, когда срез старше [maxAge].
class StaleDataBanner extends StatelessWidget {
  const StaleDataBanner({super.key, required this.asOf, this.onRefresh});

  final String asOf;
  final VoidCallback? onRefresh;

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
    final tone = AppTones.of(context).info;
    return AppCard(
      padding: AppCard.plain,
      child: Row(
        children: [
          ExcludeSemantics(
            child: Container(
              width: AppSizes.iconButton,
              height: AppSizes.iconButton,
              decoration: BoxDecoration(shape: BoxShape.circle, color: tone.bg),
              child: Icon(Icons.update, size: 20, color: tone.fg),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.staleTitle(dateShort(asOf)), style: theme.textTheme.titleSmall?.merge(AppType.numeric)),
                Text(s.staleBody, style: theme.textTheme.bodySmall?.copyWith(fontSize: 13)),
              ],
            ),
          ),
          if (onRefresh != null) ...[const SizedBox(width: AppSpacing.sm), ArrowLink(s.refresh, onTap: onRefresh)],
        ],
      ),
    );
  }
}
