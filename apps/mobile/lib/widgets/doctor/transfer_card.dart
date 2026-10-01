import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../format.dart';
import '../status_chip.dart';
import 'route_action.dart';
import 'route_notes.dart';

/// Карточка «Перевод» (веб `transfer-card`) — вместо карточки решения, когда врач сейчас не решает «оставить или
/// перевести»: перевод ждёт пациента или больницу, пациент переведён или госпитализирован, просит снять его с листа
/// ожидания, маршрут завершён, или врач — не сторона маршрута. Показывает открытый запрос пациента, статус (и причину
/// закрытия), «Перевод в …» с причиной и «тяжёлым случаем», дату госпитализации, «дата прошла», кто отвечает после
/// подтверждения и последнюю попытку. Действия — только из `progress.allowed`: «Отменить перевод» и «Снять с листа
/// ожидания» с обязательной причиной (Q-18). Принимающей больнице — ссылка на входящие, где живут её действия.
class TransferCard extends StatefulWidget {
  const TransferCard({super.key, required this.route, required this.onAction, this.busy = false, this.acting, this.onOpenIncoming});

  final PatientRoute route;
  final DoctorRouteActionHandler onAction;
  final bool busy;
  final String? acting;

  /// Перейти на вкладку «Входящие»; показывается принимающей стороне незавершённого маршрута.
  final VoidCallback? onOpenIncoming;

  @override
  State<TransferCard> createState() => _TransferCardState();
}

class _TransferCardState extends State<TransferCard> {
  final _reason = TextEditingController();
  String? _reasonError;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit(DoctorRouteAction Function(String reason) action) async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _reasonError = S.at(context).reasonRequired);
      return;
    }
    setState(() => _reasonError = null);
    final outcome = await widget.onAction(action(reason));
    if (!mounted) {
      return;
    }
    setState(() {
      _reasonError = outcome.reasonError;
      if (outcome.ok) {
        _reason.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final route = widget.route;
    final progress = route.progress!;
    final transfer = progress.transfer;
    final signal = route.openSignal;
    final attempt = progress.lastAttempt;
    final closedReason = progress.closedReason;
    final canCancel = route.can(RouteCodes.actionCancelTransfer);
    final canClose = route.can(RouteCodes.actionClose);
    final plannedAt = transfer?.plannedAt;
    final handedOver = progress.side == RouteCodes.sideOrigin && progress.responsibleMoCode.isNotEmpty && progress.responsibleMoCode != progress.originMoCode;
    final busy = widget.busy;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.patientRouteTransferTitle),
          if (signal != null) ...[const SizedBox(height: AppSpacing.md), SignalBanner(signal: signal)],
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: Text(s.routeStatusText(progress.status), style: theme.textTheme.row)),
              if (closedReason != null && closedReason.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Flexible(child: Text(s.routeClosedReason(closedReason, RouteVoice.staff), style: theme.textTheme.bodySmall, textAlign: TextAlign.end)),
              ],
            ],
          ),
          if (transfer != null && progress.status != RouteCodes.statusWithdrawalRequested) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(s.patientRouteTransferTo(shortOrgName(transfer.toMoName)), style: theme.textTheme.row),
                if (transfer.severe) StatusChip(s.routeSevereMark, tone: StatusTone.danger),
              ],
            ),
            if (transfer.reason?.trim().isNotEmpty ?? false) Text('${s.patientRouteReason}: ${transfer.reason!.trim()}', style: theme.textTheme.bodySmall),
          ],
          if (plannedAt != null && plannedAt.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(s.routeJournalPlanned(routeDate(plannedAt)), style: theme.textTheme.row.merge(AppType.numeric)),
          ],
          if (progress.overdue) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(s.patientRouteOverdue, style: theme.textTheme.bodySmall?.copyWith(color: colors.danger, fontWeight: FontWeight.w600)),
          ],
          if (handedOver) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(s.patientRouteResponsible(shortOrgName(progress.responsibleMoName)), style: theme.textTheme.bodySmall),
          ],
          if (attempt != null) ...[const SizedBox(height: AppSpacing.sm), LastAttemptLine(attempt: attempt)],
          if (canCancel || canClose) ...[
            const SizedBox(height: AppSpacing.md),
            ReasonField(
              label: s.patientRouteRequiredLabel(canClose ? s.patientRouteCloseReason : s.patientRouteCancelReason),
              controller: _reason,
              error: _reasonError,
              onChanged: (_) {
                if (_reasonError != null) {
                  setState(() => _reasonError = null);
                }
              },
            ),
            const SizedBox(height: AppSpacing.md),
            if (canClose)
              FilledButton(
                onPressed: busy ? null : () => _submit(DoctorRouteAction.close),
                child: BusyLabel(s.patientRouteClose, busy: widget.acting == RouteCodes.actionClose),
              ),
            if (canClose && canCancel) const SizedBox(height: AppSpacing.sm),
            if (canCancel)
              OutlinedButton(
                onPressed: busy ? null : () => _submit(DoctorRouteAction.cancelTransfer),
                child: BusyLabel(s.patientRouteCancel, busy: widget.acting == RouteCodes.actionCancelTransfer),
              ),
          ],
          if (widget.onOpenIncoming != null && progress.side == RouteCodes.sideReceiving && (closedReason == null || closedReason.isEmpty)) ...[
            const SizedBox(height: AppSpacing.md),
            Align(alignment: Alignment.centerLeft, child: ArrowLink(s.patientRouteToIncoming, onTap: widget.onOpenIncoming)),
          ],
        ],
      ),
    );
  }
}
