import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../format.dart';

/// Иконка уведомления по виду (NotificationBell.vue, CITIZEN_ICONS); незнакомый вид — «i».
IconData notificationIcon(String kind) => switch (kind) {
      RouteCodes.journalRedirect => Icons.swap_horiz,
      RouteCodes.journalConfirm || RouteCodes.journalReschedule => Icons.event_outlined,
      RouteCodes.journalReject || RouteCodes.journalCancel => Icons.cancel_outlined,
      RouteCodes.journalKeep => Icons.check_circle_outline,
      RouteCodes.journalAdmit => Icons.apartment_outlined,
      RouteCodes.journalDischarge => Icons.task_outlined,
      RouteCodes.journalNoShow => Icons.error_outline,
      RouteCodes.journalClose => Icons.flag_outlined,
      RouteCodes.notificationTestsExpiring => Icons.schedule,
      RouteCodes.notificationScribeConsent => Icons.mic_none,
      RouteCodes.notificationScribeLeaflet => Icons.description_outlined,
      _ => Icons.info_outline,
    };

/// Строка колокольчика гражданина (F13): точка и жирный текст у непрочитанного, приглушённый текст у прочитанного;
/// круг с иконкой вида; текст по виду с коротким именем больницы и датой; причина в «…» (кроме напоминания об
/// анализах и памятки); ниже время события (у напоминания об анализах его нет — это «сейчас») и красная метка «нужен
/// ответ». Вся строка — кнопка не ниже 56.
class NotificationTile extends StatelessWidget {
  const NotificationTile({super.key, required this.item, required this.onTap, this.last = false});

  final CitizenNotification item;
  final VoidCallback onTap;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final unread = !item.read;
    final text = s.myNotificationText(
      item.kind,
      name: shortOrgName(item.moName),
      date: routeDate(item.plannedAt),
      count: item.count ?? 0,
      needsAction: item.needsAction,
    );
    final reason = item.reason?.trim() ?? '';
    final showReason = reason.isNotEmpty && item.kind != RouteCodes.notificationTestsExpiring && item.kind != RouteCodes.notificationScribeLeaflet;
    final time = item.kind == RouteCodes.notificationTestsExpiring ? null : dateTimeShort(item.at);
    final meta = theme.textTheme.caption.merge(AppType.numeric);
    final row = Container(
      constraints: const BoxConstraints(minHeight: AppSizes.row),
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: last ? null : BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 15),
            child: Container(
              width: AppSizes.dot,
              height: AppSizes.dot,
              decoration: BoxDecoration(shape: BoxShape.circle, color: unread ? colors.accent : ColorTokens.transparent),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          ExcludeSemantics(
            child: Container(
              width: AppSizes.small,
              height: AppSizes.small,
              decoration: BoxDecoration(shape: BoxShape.circle, color: unread ? colors.accentSoft : colors.surfaceSunken),
              child: Icon(notificationIcon(item.kind), size: 18, color: unread ? colors.accentHover : colors.muted),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: unread ? theme.textTheme.rowStrong : theme.textTheme.row.copyWith(color: colors.muted)),
                if (showReason) Text('«$reason»', style: theme.textTheme.rowDetail.copyWith(color: colors.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (time != null || item.needsAction)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text.rich(
                      TextSpan(children: [
                        if (time != null) TextSpan(text: time),
                        if (time != null && item.needsAction) const TextSpan(text: ' · '),
                        if (item.needsAction) TextSpan(text: s.myNeedsAnswer, style: TextStyle(color: colors.danger, fontWeight: FontWeight.w700)),
                      ]),
                      style: meta,
                    ),
                  ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.only(top: AppSpacing.sm), child: Icon(Icons.chevron_right, size: 20, color: colors.muted)),
        ],
      ),
    );
    return Semantics(button: true, child: InkWell(onTap: onTap, child: row));
  }
}
