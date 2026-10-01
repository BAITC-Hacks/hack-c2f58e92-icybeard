import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../state/session.dart';
import '../../theme/tokens.dart';
import '../app_card.dart';
import '../format.dart';
import '../route/consent_chip.dart';
import '../signal_card.dart';
import 'citizen_action_button.dart';
import 'citizen_actions.dart';

/// Ответ врача, пока пациент ждёт в своей больнице (R-8, RouteCitizenView.vue `doctor-answer`): «Врач предложил
/// другую организацию» с ожиданием там («Достар Мед · ≈ 4 дн. — половина ждёт не дольше») или «Врач оставил в
/// текущей организации», причина врача, чип согласия (только принято / отказано), «Понятно» прячет карточку
/// навсегда (решение Q6, `Session.markDecisionSeen`) и ссылка «Сравнить ожидание» на «Сколько ждут» с профилем
/// маршрута.
class DoctorAnswerCard extends StatelessWidget {
  const DoctorAnswerCard({super.key, required this.route, required this.decision});

  final PatientRoute route;
  final RouteDecision decision;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final redirect = decision.kind == RouteCodes.redirect;
    final alternative = route.alternatives.where((a) => a.moCode == decision.toMoCode).firstOrNull;
    final reason = decision.reason?.trim() ?? '';
    final consent = decision.patientConsent;
    return SignalCard(
      title: redirect ? s.myDoctorSuggested : s.myDoctorKept,
      lines: [
        if (redirect)
          Text(
            '${shortOrgName(decision.toMoName)}${alternative == null ? '' : ' · ${approxDays(alternative.p50Days)} ${s.daysUnit} — ${s.myHalfWaits}'}',
            style: theme.textTheme.bodyMedium,
          ),
        if (reason.isNotEmpty) Text(s.myDoctorReason(reason), style: theme.textTheme.bodySmall),
        if (consent != null && consent != RouteCodes.consentPending)
          Align(alignment: AlignmentDirectional.centerStart, child: ConsentChip(consent, voice: RouteVoice.citizen)),
      ],
      actions: [
        FilledButton(onPressed: () => context.read<Session>().markDecisionSeen(decision.decisionId), child: Text(s.gotIt)),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: ArrowLink(
            s.myCompareWait,
            onTap: () => context.go(Uri(path: '/home/wait', queryParameters: {'region': route.regionKato, 'profile': route.organization.profileCode}).toString()),
          ),
        ),
      ],
    );
  }
}

/// «Вы ещё ждёте госпитализацию?» (F10): «Да, жду» сразу, «Уже лечился в другом месте» сразу, «Больше не нужно» —
/// через лист подтверждения (Q5). Последние две — только если сервер разрешает `withdraw`.
class ValidationCard extends StatelessWidget {
  const ValidationCard({super.key, required this.route});

  final PatientRoute route;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final withdraw = route.can(RouteCodes.actionWithdraw);
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.validationTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(s.validationBody, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.md),
          CitizenActionButton(label: s.validationStill, onPressed: () => stillWaiting(context)),
          if (withdraw) ...[
            const SizedBox(height: AppSpacing.sm),
            CitizenActionButton(label: s.validationTreated, kind: CitizenButtonKind.secondary, onPressed: () => treatedElsewhere(context)),
            const SizedBox(height: AppSpacing.sm),
            CitizenActionButton(label: s.validationWithdraw, kind: CitizenButtonKind.secondary, onPressed: () => withdrawFromList(context)),
          ],
        ],
      ),
    );
  }
}
