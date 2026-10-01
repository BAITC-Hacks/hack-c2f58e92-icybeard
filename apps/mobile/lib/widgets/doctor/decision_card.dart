import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../app_card.dart';
import '../origin_tag.dart';
import 'decision_option.dart';
import 'route_action.dart';
import 'route_notes.dart';

/// Карточка «Оставить или перевести» (веб `decision-card`, поток 4a) — только когда `progress.allowed` содержит
/// `keep` или `redirect`: открытый запрос пациента с комментарием, последняя несостоявшаяся попытка, «пациент просит
/// оставить его в своей больнице», выбор больницы (альтернативы маршрута и больница из запроса пациента), общая
/// обязательная причина, отметка «Тяжёлый случай» (только при выбранной больнице; снятый выбор снимает и её), кнопки
/// «Перевести в выбранную» и «Оставить в текущей» — каждая только если её разрешил сервер. Пустая причина — подсказка
/// у поля без запроса; 422 — сообщение сервера у поля. Ниже — ассистент для нового направления (Q-5).
class DecisionCard extends StatefulWidget {
  const DecisionCard({super.key, required this.route, required this.onAction, this.busy = false, this.acting, this.regionNames = const {}, this.onAssistant});

  final PatientRoute route;
  final DoctorRouteActionHandler onAction;

  /// Любое действие маршрута в полёте — кнопки выключены.
  final bool busy;

  /// Код действия в полёте — у его кнопки индикатор.
  final String? acting;

  /// Названия регионов по КАТО — для «сосед: …» у больниц соседнего региона.
  final Map<String, String> regionNames;

  /// Ассистент направления с больницей и профилем маршрута; null — нет `referral.assist`.
  final VoidCallback? onAssistant;

  @override
  State<DecisionCard> createState() => _DecisionCardState();
}

class _DecisionCardState extends State<DecisionCard> {
  final _reason = TextEditingController();
  String? _choice;
  bool _severe = false;
  String? _reasonError;

  @override
  void didUpdateWidget(DecisionCard old) {
    super.didUpdateWidget(old);
    // после перечитывания выбранной больницы может не быть в списке (отказала, пациент отклонил) — выбор снимается
    if (_choice != null && !decisionChoices(widget.route).any((c) => c.moCode == _choice)) {
      _choice = null;
      _severe = false;
    }
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _toggle(String moCode) => setState(() {
        _choice = _choice == moCode ? null : moCode;
        if (_choice == null) {
          _severe = false;
        }
      });

  Future<void> _submit(DoctorRouteAction Function(String reason) action) async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _reasonError = S.at(context).patientRouteReasonMissing);
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
        _choice = null;
        _severe = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final route = widget.route;
    final progress = route.progress;
    final canRedirect = route.can(RouteCodes.actionRedirect);
    final canKeep = route.can(RouteCodes.actionKeep);
    final choices = canRedirect ? decisionChoices(route) : const <DecisionChoice>[];
    final signal = route.openSignal;
    final attempt = progress?.lastAttempt;
    final busy = widget.busy;
    final choice = _choice;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.patientRouteWhereTitle, trailing: route.alternativesModel == null ? null : const OriginTag(Origin.ml)),
          if (signal != null) ...[const SizedBox(height: AppSpacing.md), SignalBanner(signal: signal)],
          if (attempt != null) ...[const SizedBox(height: AppSpacing.sm), LastAttemptLine(attempt: attempt)],
          if (progress?.prefersCurrent ?? false) ...[const SizedBox(height: AppSpacing.sm), Text(s.patientRoutePrefersCurrent, style: theme.textTheme.bodySmall)],
          if (canRedirect) ...[
            const SizedBox(height: AppSpacing.sm),
            if (choices.isEmpty)
              Text(s.routeNoAlternatives, style: theme.textTheme.bodySmall)
            else
              for (final (i, c) in choices.indexed)
                DecisionOptionTile(
                  choice: c,
                  selected: c.moCode == choice,
                  last: i == choices.length - 1,
                  neighbourRegion: c.alternative?.isNeighborRegion ?? false ? widget.regionNames[c.alternative!.regionKato] ?? c.alternative!.regionKato : null,
                  onTap: busy ? null : () => _toggle(c.moCode),
                ),
          ],
          const SizedBox(height: AppSpacing.md),
          ReasonField(
            label: s.patientRouteRequiredLabel(s.patientRouteReasonLabel),
            controller: _reason,
            hint: s.patientRouteReasonExample,
            error: _reasonError,
            onChanged: (_) {
              if (_reasonError != null) {
                setState(() => _reasonError = null);
              }
            },
          ),
          if (canRedirect)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _severe,
              onChanged: choice == null || busy ? null : (value) => setState(() => _severe = value),
              title: Text(s.patientRouteSevere, style: theme.textTheme.bodyMedium),
              subtitle: choice == null ? Text(s.patientRouteSevereOff, style: theme.textTheme.bodySmall) : null,
            ),
          const SizedBox(height: AppSpacing.sm),
          if (canRedirect)
            FilledButton(
              onPressed: choice == null || busy ? null : () => _submit((reason) => DoctorRouteAction.redirect(choice, reason, severe: _severe)),
              child: BusyLabel(s.patientRouteTransfer, busy: widget.acting == RouteCodes.actionRedirect),
            ),
          if (canRedirect && canKeep) const SizedBox(height: AppSpacing.sm),
          if (canKeep)
            OutlinedButton(
              onPressed: busy ? null : () => _submit(DoctorRouteAction.keep),
              child: BusyLabel(s.patientRouteKeep, busy: widget.acting == RouteCodes.actionKeep),
            ),
          if (widget.onAssistant != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(s.patientRouteAssistantHint, style: theme.textTheme.bodySmall),
            Align(alignment: Alignment.centerLeft, child: ArrowLink(s.patientRouteToAssistant, onTap: widget.onAssistant)),
          ],
        ],
      ),
    );
  }
}
