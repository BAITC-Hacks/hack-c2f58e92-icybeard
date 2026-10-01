import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/strings.dart';
import '../state/staff_bell_notifier.dart';
import 'circle_button.dart';
import 'count_badge.dart';

/// Кнопка-колокольчик персонала для шапки рабочего списка (Q-1): круглая кнопка 40 со счётчиком непрочитанного
/// [StaffBellNotifier.totalUnread] (ждут подтверждения + подтверждения, выписки, события пациентов) — как колокольчик
/// веба. Нажатие открывает `/doctor/notifications` через `push`, чтобы «назад» вернул к списку. Колокольчик есть только
/// у тех, кому он положен (`worklist.view` и своя организация): без провайдера (тест отдельного экрана) и у
/// администратора без больницы кнопки нет. Подпись для чтения с экрана — «Уведомления, новых: N».
class BellButton extends StatelessWidget {
  const BellButton({super.key});

  /// Куда ведёт кнопка.
  static const target = '/doctor/notifications';

  @override
  Widget build(BuildContext context) {
    final bell = StaffBellNotifier.watchBell(context);
    if (!bell.active) {
      return const SizedBox.shrink();
    }
    final s = S.at(context);
    return CountBadge(
      count: bell.unread,
      child: CircleIconButton(icon: Icons.notifications_none, label: s.bellSemantics(bell.unread), onTap: () => context.push(target)),
    );
  }
}
