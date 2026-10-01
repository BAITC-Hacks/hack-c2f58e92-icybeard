import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../format.dart';
import '../signal_card.dart';
import 'citizen_action_button.dart';
import 'citizen_actions.dart';

/// Карточка состояния маршрута вне листа ожидания своей больницы (F1–F6, RouteCitizenView.vue `route-progress`):
/// заголовок и текст по `progress.status`, причина врача у предложения перевода, «Дата прошла…» при `overdue`;
/// кнопки — только из `progress.allowed`: «Согласен», «Отказаться» / «Отозвать согласие», «Я ещё жду», ссылка
/// «Больше не нужно» / «Отказаться от госпитализации». Одна и та же карточка на главной и в «Моём пути» (Q2).
/// Закрытый маршрут — фразой журнала во втором лице (Q4).
class RouteStateCard extends StatelessWidget {
  const RouteStateCard({super.key, required this.route});

  final PatientRoute route;

  @override
  Widget build(BuildContext context) {
    final progress = route.progress;
    if (progress == null) {
      return const SizedBox.shrink();
    }
    final s = S.at(context);
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall;
    final transfer = progress.transfer;
    final status = progress.status;
    final (title, body) = _texts(s, progress);
    final reason = transfer?.reason?.trim() ?? '';
    return SignalCard(
      icon: Icons.shield_outlined,
      title: title,
      lines: [
        if (body.isNotEmpty) Text(body, style: theme.textTheme.bodyMedium),
        if (status == RouteCodes.statusTransferPendingConsent && reason.isNotEmpty) Text(s.myDoctorReason(reason), style: muted),
        if (progress.overdue) Text(s.myOverdueBody, style: muted),
      ],
      actions: [
        if (transfer != null && route.can(RouteCodes.actionAcceptTransfer))
          CitizenActionButton(label: s.myConsentAccept, onPressed: () => acceptTransfer(context, transfer)),
        if (transfer != null && route.can(RouteCodes.actionDeclineTransfer))
          CitizenActionButton(
            label: status == RouteCodes.statusTransferPendingConfirmation ? s.myWithdrawConsent : s.myConsentDecline,
            kind: CitizenButtonKind.secondary,
            onPressed: () => declineTransfer(context, transfer, withdrawingConsent: status == RouteCodes.statusTransferPendingConfirmation),
          ),
        if (route.can(RouteCodes.actionStillWaiting)) CitizenActionButton(label: s.myStillWaiting, onPressed: () => stillWaiting(context)),
        if (route.can(RouteCodes.actionWithdraw) && status != RouteCodes.statusWithdrawalRequested)
          CitizenActionButton(
            label: status == RouteCodes.statusTransferred ? s.myRefuseHospital : s.validationWithdraw,
            kind: CitizenButtonKind.link,
            onPressed: () => withdrawFromList(context, refuseHospital: status == RouteCodes.statusTransferred),
          ),
      ],
    );
  }

  /// Заголовок и текст карточки по статусу. Больница перевода — короткое имя цели перевода, а после подтверждения —
  /// ответственной больницы (принимающей). Незнакомый статус — его подпись для персонала (или код) без текста.
  static (String, String) _texts(S s, RouteProgress p) {
    final name = shortOrgName(p.transfer?.toMoName ?? p.responsibleMoName);
    final responsible = shortOrgName(p.responsibleMoName);
    return switch (p.status) {
      RouteCodes.statusTransferPendingConsent => (s.routeConsentState(RouteCodes.consentPending, RouteVoice.citizen), s.myProposedBody(name)),
      RouteCodes.statusTransferPendingConfirmation => (s.myWaitConfirmTitle, s.myWaitConfirmBody(name)),
      RouteCodes.statusTransferred => (s.myTransferredTitle, s.myTransferredBody(name, routeDate(p.transfer?.plannedAt))),
      RouteCodes.statusAdmitted => (s.myAdmittedTitle, responsible),
      RouteCodes.statusWithdrawalRequested => (s.myWithdrawalTitle, s.myWithdrawalBody),
      RouteCodes.statusClosed => (
          s.routeStatusText(RouteCodes.statusClosed),
          p.closedReason == null ? '' : s.routeClosedReason(p.closedReason!, RouteVoice.citizen, name: responsible),
        ),
      _ => (s.routeStatusText(p.status), ''),
    };
  }
}
