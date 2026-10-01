import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';

/// Переключатель события «Изменения моего маршрута» (`route_updates`, канал «в системе»; решение Q12) на экране
/// настроек уведомлений гражданина: название события — из API на языке интерфейса, подпись — что приходит всегда.
/// Выключенный канал убирает из колокольчика новости маршрута, но не то, что ждёт ответа.
class RouteUpdatesCard extends StatelessWidget {
  const RouteUpdatesCard({super.key, required this.event, required this.onChanged, this.busy = false});

  final NotificationEvent event;
  final ValueChanged<bool> onChanged;

  /// Сохранение в полёте — переключатель заблокирован.
  final bool busy;

  /// Название события на языке [locale]; без названий — код.
  static String titleOf(NotificationEvent event, String locale) {
    final kk = event.titleKk?.trim() ?? '';
    final ru = event.titleRu?.trim() ?? '';
    if (locale == 'kk' && kk.isNotEmpty) {
      return kk;
    }
    return ru.isNotEmpty ? ru : event.code;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return AppCard(
      padding: AppCard.plain,
      child: MergeSemantics(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titleOf(event, s.locale), style: theme.textTheme.row),
                  const SizedBox(height: AppSpacing.xs),
                  Text(s.routeUpdatesAlways, style: theme.textTheme.rowDetail.copyWith(color: colors.muted)),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Switch(value: event.inApp, onChanged: busy ? null : onChanged),
          ],
        ),
      ),
    );
  }
}
