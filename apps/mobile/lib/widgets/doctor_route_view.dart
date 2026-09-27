import 'package:flutter/material.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import 'app_card.dart';
import 'collapsible_section.dart';
import 'explanation_card.dart';
import 'format.dart';
import 'org_name.dart';
import 'origin_tag.dart';
import 'route_sections.dart';

/// Тело «Маршрут пациента» для врача: реф 24/500 и подпись «профиль · ждёт N дн. · приоритет P»; карточка
/// «Рекомендация» (лучшая альтернатива 20/500, hero «≈ N дн. · половина ждёт не дольше», «Риск отказа X %»,
/// следующий шаг, запрос пациента); «Альтернативы в регионе» строками (текущая первой); карточка открытого сигнала
/// с полем причины и действиями; свёрнутые секции. Риск отказа показывается только здесь.
class DoctorRouteView extends StatelessWidget {
  const DoctorRouteView({super.key, required this.route, this.busy = false, this.onRedirect, this.onKeep});

  final PatientRoute route;
  final bool busy;

  /// Перенаправление: с причиной из карточки сигнала или без неё (экран спросит листом).
  final void Function(Alternative alternative, {String? reason})? onRedirect;

  /// «Оставить» с причиной — ответ на сигнал пациента.
  final void Function(String reason)? onKeep;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final doctor = route.doctor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(route.patientRef, style: theme.textTheme.headlineSmall?.merge(AppType.numeric)),
        const SizedBox(height: AppSpacing.xs),
        Text(
          [route.organization.profileName, s.waitingFor(route.daysWaiting), if (doctor != null) s.priorityLine(doctor.priority)].join(' · '),
          style: theme.textTheme.bodySmall?.merge(AppType.numeric),
        ),
        const SizedBox(height: AppSpacing.md),
        _RecommendationCard(route: route),
        const SizedBox(height: AppSpacing.md),
        _AlternativesCard(route: route, onRedirect: busy ? null : onRedirect),
        if (route.openSignal != null) ...[
          const SizedBox(height: AppSpacing.md),
          _SignalCard(route: route, busy: busy, onRedirect: onRedirect, onKeep: onKeep),
        ],
        if (doctor?.shap != null) ...[
          const SizedBox(height: AppSpacing.md),
          CollapsibleSection(title: s.whySo, summary: '${doctor!.shap!.factors.length}', origin: Origin.ml, child: FactorList(explanation: doctor.shap!, model: route.forecast.model)),
        ],
        const SizedBox(height: AppSpacing.md),
        ChecklistSection(route: route),
        const SizedBox(height: AppSpacing.sm),
        StagesSection(route: route),
        const SizedBox(height: AppSpacing.sm),
        SignalsSection(route: route, doctorMode: true),
        const SizedBox(height: AppSpacing.sm),
        HistorySection(route: route),
        const SizedBox(height: AppSpacing.lg),
        Text(route.basis, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// Лучшая альтернатива по p50; null, если альтернатив нет.
Alternative? bestAlternative(PatientRoute route) =>
    route.alternatives.isEmpty ? null : route.alternatives.reduce((a, b) => a.p50Days <= b.p50Days ? a : b);

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({required this.route});

  final PatientRoute route;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final f = route.forecast;
    final doctor = route.doctor;
    final best = bestAlternative(route);
    final signal = route.openSignal;
    final risk = doctor == null ? null : (doctor.refusalOrgInTraining ? pct(doctor.pRefusal) : s.refusalAboveAverage);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardLabel(best == null ? s.forecastLabel : s.recommendationLabel, trailing: OriginTag(f.fromModel ? Origin.ml : Origin.formula)),
          const SizedBox(height: AppSpacing.md),
          OrgName(best?.name ?? route.organization.moName, style: theme.textTheme.titleLarge, maxLines: 2),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text('≈ ${days(best?.p50Days ?? f.p50Days)}', style: theme.textTheme.displayMedium?.merge(AppType.numeric))),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: Text(s.halfNoLonger, style: theme.textTheme.bodySmall?.copyWith(fontSize: 17), maxLines: 2)),
            ],
          ),
          if (risk != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(s.riskRefusalLine(risk), style: theme.textTheme.bodySmall?.copyWith(fontSize: 17).merge(AppType.numeric)),
            if (!doctor!.refusalOrgInTraining) Text(s.refusalOrgUnknownNote, style: theme.textTheme.labelSmall?.copyWith(color: colors.muted)),
          ],
          if (doctor != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text('${s.nextActionLabel}: ${s.nextActionText(doctor.nextActionCode, doctor.nextAction)}', style: theme.textTheme.bodySmall),
          ],
          if (signal != null && signal.kind == RouteCodes.requestRedirect) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              [
                '${s.patientRequestPrefix} ${shortOrgName(signal.toMoName ?? signal.toMoCode ?? '')}',
                if (signal.comment != null && signal.comment!.isNotEmpty) '«${signal.comment}»',
              ].join(' — '),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (!f.fromModel) ...[const SizedBox(height: AppSpacing.sm), Text(s.modelUnavailableNote, style: theme.textTheme.labelSmall)],
        ],
      ),
    );
  }
}

/// «Альтернативы в регионе»: текущая организация первой с прогнозом маршрута, затем альтернативы «≈ N дн.»;
/// тап по альтернативе — перенаправить (лист причины).
class _AlternativesCard extends StatelessWidget {
  const _AlternativesCard({required this.route, this.onRedirect});

  final PatientRoute route;
  final void Function(Alternative alternative, {String? reason})? onRedirect;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final f = route.forecast;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CardLabel(s.alternativesSection),
          ListRow(
            title: shortOrgName(route.organization.moName),
            subtitle: s.currentOrgTag,
            last: route.alternatives.isEmpty,
            trailing: RowValue('${days(f.p50Days)} ${s.daysUnit}', strong: true, size: 15),
          ),
          for (final (i, a) in route.alternatives.indexed)
            ListRow(
              title: shortOrgName(a.name),
              subtitle: a.pRefusal > 0 ? s.riskShort(pct(a.pRefusal)) : null,
              last: i == route.alternatives.length - 1,
              trailing: RowValue('≈ ${days(a.p50Days)} ${s.daysUnit}', strong: true, size: 15),
              chevron: false,
              onTap: onRedirect == null ? null : () => onRedirect!(a),
            ),
          if (route.alternatives.isEmpty)
            Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: Text(s.noQueuesInRegion, style: theme.textTheme.bodySmall?.copyWith(color: colors.muted))),
        ],
      ),
    );
  }
}

/// Открытый сигнал пациента: «Пациент просит Достар Мед», комментарий, поле причины и два действия — оба пишут
/// решение в журнал и закрывают сигнал. Без `referral.confirm` (нет обработчиков) — только сам сигнал.
class _SignalCard extends StatefulWidget {
  const _SignalCard({required this.route, required this.busy, this.onRedirect, this.onKeep});

  final PatientRoute route;
  final bool busy;
  final void Function(Alternative alternative, {String? reason})? onRedirect;
  final void Function(String reason)? onKeep;

  @override
  State<_SignalCard> createState() => _SignalCardState();
}

class _SignalCardState extends State<_SignalCard> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final signal = widget.route.openSignal!;
    final requested = widget.route.alternatives.where((a) => a.moCode == signal.toMoCode).firstOrNull;
    final title = signal.kind == RouteCodes.requestRedirect
        ? s.patientAsksTitle(shortOrgName(signal.toMoName ?? signal.toMoCode ?? ''))
        : s.patientSignalText(signal.kind, null);
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            [dateTimeShort(signal.recordedAt), if (signal.comment != null && signal.comment!.isNotEmpty) '«${signal.comment}»'].join(' · '),
            style: theme.textTheme.bodySmall?.merge(AppType.numeric),
          ),
          if (widget.onRedirect != null || widget.onKeep != null) ...[
            const SizedBox(height: AppSpacing.md),
            FieldLabel(s.keepReasonLabel),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _reason,
              builder: (_, value, _) {
                final canAct = !widget.busy && value.text.trim().isNotEmpty;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(controller: _reason, maxLines: 2, decoration: InputDecoration(hintText: s.reasonHint)),
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      children: [
                        if (requested != null && widget.onRedirect != null) ...[
                          Expanded(child: FilledButton(onPressed: canAct ? () => widget.onRedirect!(requested, reason: value.text.trim()) : null, child: Text(s.redirectHere))),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        if (widget.onKeep != null)
                          Expanded(child: OutlinedButton(onPressed: canAct ? () => widget.onKeep!(value.text.trim()) : null, child: Text(s.keepHere))),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
