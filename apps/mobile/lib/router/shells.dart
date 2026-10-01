import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../l10n/strings.dart';
import '../state/citizen_notifications_notifier.dart';
import '../state/session.dart';
import '../state/staff_bell_notifier.dart';
import '../widgets/app_shell.dart';
import 'app_router.dart';

/// Гражданский shell: [AppShell] с вкладками [citizenDestinations]; счётчик «Уведомлений» — непрочитанное
/// колокольчика гражданина ([CitizenNotificationsNotifier]). Перестраивается при смене языка и счётчика.
class CitizenShell extends StatelessWidget {
  const CitizenShell({super.key, required this.shell, required this.session});

  final StatefulNavigationShell shell;
  final Session session;

  @override
  Widget build(BuildContext context) =>
      AppShell(shell: shell, destinations: citizenDestinations(S.at(context), session, unread: CitizenNotificationsNotifier.unreadOf(context)));
}

/// Врачебный shell: [AppShell] с вкладками [doctorDestinations]; счётчик «Входящих» — переводы, ждущие подтверждения
/// приёма ([StaffBellNotifier]). Перестраивается при смене языка и счётчика.
class DoctorShell extends StatelessWidget {
  const DoctorShell({super.key, required this.shell, required this.session});

  final StatefulNavigationShell shell;
  final Session session;

  @override
  Widget build(BuildContext context) =>
      AppShell(shell: shell, destinations: doctorDestinations(S.at(context), session, pendingIncoming: StaffBellNotifier.pendingIncomingOf(context)));
}
