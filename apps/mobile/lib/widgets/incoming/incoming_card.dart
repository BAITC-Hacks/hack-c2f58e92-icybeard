import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../app_card.dart';
import '../format.dart';
import '../org_name.dart';
import '../route/consent_chip.dart';
import '../route/route_journal.dart';
import '../status_chip.dart';
import 'incoming_filter.dart';

/// Карточка входящего направления (доска 03 §6.3) вместо строки таблицы веба — одна колонка: реф пациента (после
/// подтверждения — ссылка на маршрут) и отметка «Тяжёлый случай»; профиль койки; направившая больница (короткое имя,
/// тап — полное) и её код; когда предложен перевод и согласие пациента; статус маршрута с причиной закрытия; дата
/// госпитализации и «Дата прошла»; кнопки — только из `item.allowed` ([incomingActions]). Выписанная строка — зелёная
/// отметка «Выписан», строка без действий — «действий нет». Если пациент просит снять его с листа ожидания (`close`
/// в `allowed`), ведёт «Открыть маршрут»: снимают на странице пациента (Q-18). Пока идёт любое действие, все кнопки
/// выключены ([busy]); полоска прогресса — у карточки, чьё действие в полёте ([acting]).
class IncomingCard extends StatelessWidget {
  const IncomingCard({
    super.key,
    required this.item,
    this.profileName = '',
    this.canAct = true,
    this.busy = false,
    this.acting = false,
    required this.onAction,
    this.onOpenRoute,
  });

  final IncomingReferral item;

  /// Название профиля койки из справочника; пусто — показывается код.
  final String profileName;

  /// У пользователя есть `referral.confirm`: без него действий нет даже при непустом `allowed`.
  final bool canAct;

  /// Какое-то действие в полёте — все кнопки выключены.
  final bool busy;

  /// В полёте действие этой карточки.
  final bool acting;

  /// Нажата кнопка: код действия (`RouteCodes.action*`).
  final ValueChanged<String> onAction;

  /// Открыть маршрут пациента; null — ещё не подтверждено (маршрут принимающей больнице не открыт).
  final VoidCallback? onOpenRoute;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final actions = canAct ? incomingActions(item) : const <String>[];
    final status = item.status;
    final plannedAt = item.plannedAt;
    final profile = profileName.isEmpty ? item.profileCode : profileName;
    // имя направившей больницы неизвестно серверу — он отдаёт код вместо имени: код второй раз не пишем
    final senderCode = item.fromMoCode.isEmpty || item.fromMoName == item.fromMoCode ? '' : ' · ${item.fromMoCode}';
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(item: item, onOpenRoute: onOpenRoute),
          const SizedBox(height: AppSpacing.sm),
          if (profile.isNotEmpty) Text(profile, style: theme.textTheme.row),
          OrgName(item.fromMoName, suffix: senderCode, maxLines: 2),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(journalMoment(item.recordedAt), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
              ConsentChip(item.patientConsent, voice: RouteVoice.staff),
            ],
          ),
          if (status != null && status.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(s.routeStatusLine(status, closedReason: item.closedReason), style: theme.textTheme.bodyMedium?.copyWith(color: colors.ink)),
          ],
          if (plannedAt != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(s.routeJournalPlanned(routeDate(plannedAt)), style: theme.textTheme.bodySmall?.merge(AppType.numeric)),
                if (item.overdue) StatusChip(s.incomingOverdue, tone: StatusTone.danger),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          if (acting) ...[const LinearProgressIndicator(minHeight: 2), const SizedBox(height: AppSpacing.sm)],
          _Actions(item: item, actions: actions, busy: busy, onAction: onAction),
          if (onOpenRoute != null && item.can(RouteCodes.actionClose)) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(alignment: Alignment.centerLeft, child: ArrowLink(s.openRoute, onTap: onOpenRoute)),
          ],
        ],
      ),
    );
  }
}

/// Реф пациента (табличные цифры) и «Тяжёлый случай». После подтверждения реф — ссылка цвета `--link` со стрелкой,
/// цель нажатия не меньше 44.
class _Header extends StatelessWidget {
  const _Header({required this.item, this.onOpenRoute});

  final IncomingReferral item;
  final VoidCallback? onOpenRoute;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final link = onOpenRoute != null;
    final ref = Text(
      item.patientRef,
      style: theme.textTheme.rowStrong.copyWith(color: link ? colors.link : colors.ink).merge(AppType.numeric),
    );
    final head = Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (link) Row(mainAxisSize: MainAxisSize.min, children: [Flexible(child: ref), Icon(Icons.chevron_right, size: 20, color: colors.link)]) else ref,
        if (item.severe) StatusChip(s.routeSevereMark, tone: StatusTone.danger),
      ],
    );
    if (!link) {
      return head;
    }
    return Semantics(
      button: true,
      excludeSemantics: true,
      label: '${s.openRoute}: ${item.patientRef}${item.severe ? ', ${s.routeSevereMark}' : ''}',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onOpenRoute,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppSizes.compact),
          child: Align(alignment: Alignment.centerLeft, child: head),
        ),
      ),
    );
  }
}

/// Кнопки действий в порядке веба, переносятся строками; «Подтвердить приём» и «Госпитализирован» — primary,
/// «Выписать» — primary, если «Госпитализирован» не предложен. Высота 44 — под палец.
class _Actions extends StatelessWidget {
  const _Actions({required this.item, required this.actions, required this.busy, required this.onAction});

  final IncomingReferral item;
  final List<String> actions;
  final bool busy;
  final ValueChanged<String> onAction;

  bool _primary(String action) =>
      action == RouteCodes.actionConfirm ||
      action == RouteCodes.actionAdmit ||
      (action == RouteCodes.actionDischarge && !actions.contains(RouteCodes.actionAdmit));

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    if (item.discharged) {
      return Align(alignment: Alignment.centerLeft, child: StatusChip(s.incomingDischargedMark, tone: StatusTone.ok, icon: Icons.check));
    }
    if (actions.isEmpty) {
      return Text(s.incomingNoActions, style: theme.textTheme.labelSmall);
    }
    final style = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, AppSizes.compact)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: AppSpacing.lg)),
      textStyle: WidgetStatePropertyAll(theme.textTheme.titleSmall),
    );
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final action in actions)
          _primary(action)
              ? FilledButton(style: style, onPressed: busy ? null : () => onAction(action), child: Text(incomingActionLabel(s, action)))
              : OutlinedButton(style: style, onPressed: busy ? null : () => onAction(action), child: Text(incomingActionLabel(s, action))),
      ],
    );
  }
}

/// Подпись кнопки действия входящего направления; незнакомый код — сам код (до экрана он не доходит, см.
/// [incomingActions]).
String incomingActionLabel(S s, String action) => switch (action) {
      RouteCodes.actionConfirm => s.incomingConfirmAction,
      RouteCodes.actionReject => s.incomingRejectAction,
      RouteCodes.actionAdmit => s.incomingAdmitAction,
      RouteCodes.actionDischarge => s.incomingDischargeAction,
      RouteCodes.actionReschedule => s.incomingRescheduleAction,
      RouteCodes.actionNoShow => s.incomingNoShowAction,
      _ => action,
    };
