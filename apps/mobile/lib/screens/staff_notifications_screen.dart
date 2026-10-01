import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../widgets/empty_state.dart';
import '../widgets/section.dart';

/// Уведомления персонала: `/doctor/notifications` вне вкладок, открывается кнопкой-колокольчиком рабочего списка
/// (`context.push`, чтобы «назад» вернул к списку). Данные — `StaffBellNotifier` над приложением. Заглушка волны 1:
/// заголовок и пустое состояние; список подтверждений, выписок и событий пациентов строит экран волны 2.
class StaffNotificationsScreen extends StatelessWidget {
  const StaffNotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return PageScaffold(
      title: s.bellTitle,
      children: [EmptyState(icon: Icons.notifications_none, title: s.bellEmpty)],
    );
  }
}
