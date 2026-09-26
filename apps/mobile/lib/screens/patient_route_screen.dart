import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/doctor_route_view.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_box.dart';
import '../widgets/format.dart';
import '../widgets/org_name.dart';
import '../widgets/picker_sheet.dart';
import '../widgets/redirect_reason_dialog.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';

/// Маршрут пациента для врача: реф в шапке, панель врача первой, сигнал пациента с полем причины, прогноз и
/// свёрнутые секции; липкая панель «Направить» (лист альтернатив → причина) и «Ассистент». Перенаправление и
/// «Оставить» пишутся одним Idempotency-Key на нажатие; после записи маршрут перечитывается.
class PatientRouteScreen extends StatefulWidget {
  const PatientRouteScreen({super.key, required this.patientRef, this.preview});

  final String patientRef;
  final WorklistItem? preview;

  @override
  State<PatientRouteScreen> createState() => _PatientRouteScreenState();
}

class _PatientRouteScreenState extends State<PatientRouteScreen> {
  LoadState<PatientRoute> _state = const Loading();
  bool _busy = false;

  PatientRoute? get _route => switch (_state) { Loaded<PatientRoute>(:final data) => data, _ => null };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const Loading());
    try {
      final route = await context.read<Session>().api.patientRoute(widget.patientRef);
      if (mounted) {
        setState(() => _state = Loaded(route));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  Future<void> _redirect(Alternative alternative, {String? reason}) async {
    final s = S.at(context);
    final text = reason ?? await RedirectReasonDialog.show(context, organization: alternative.name, subtitle: '≈ ${days(alternative.p50Days)} ${s.daysUnit}');
    if (text == null || text.isEmpty || !mounted) {
      return;
    }
    await _record(() => context.read<Session>().api.redirectRoute(widget.patientRef, toMoCode: alternative.moCode, reason: text, idempotencyKey: newIdempotencyKey()), s.redirectDone);
  }

  Future<void> _keep(String reason) async {
    final s = S.at(context);
    await _record(() => context.read<Session>().api.keepRoute(widget.patientRef, reason: reason, idempotencyKey: newIdempotencyKey()), s.keepDone);
  }

  /// «Направить» из липкой панели: лист альтернатив, затем причина.
  Future<void> _referSheet() async {
    final s = S.at(context);
    final route = _route;
    if (route == null || route.alternatives.isEmpty) {
      return;
    }
    final moCode = await PickerSheet.show<String>(
      context,
      title: s.whereToRefer,
      items: [
        for (final a in route.alternatives)
          PickerItem(a.moCode, shortOrgName(a.name), detail: '≈ ${days(a.p50Days)} ${s.daysUnit} · ${s.riskShort(pct(a.pRefusal))}'),
      ],
      search: route.alternatives.length > 5,
    );
    final chosen = route.alternatives.where((a) => a.moCode == moCode).firstOrNull;
    if (chosen != null && mounted) {
      await _redirect(chosen);
    }
  }

  Future<void> _record(Future<String> Function() call, String done) async {
    final s = S.at(context);
    setState(() => _busy = true);
    try {
      await call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.serverUnavailable(e))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _openAssistant() {
    final route = _route;
    final preview = widget.preview;
    final moCode = route?.organization.moCode ?? preview?.moCode ?? '';
    final profile = route?.organization.profileCode ?? preview?.profileCode ?? '';
    context.go('/doctor/patients/${Uri.encodeComponent(widget.patientRef)}/referral?moCode=$moCode&profileCode=$profile');
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final preview = widget.preview;
    final route = _route;
    return PageScaffold(
      title: widget.patientRef,
      onRefresh: _load,
      bottom: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy || route == null || route.alternatives.isEmpty ? null : _referSheet,
                  icon: const Icon(Icons.alt_route),
                  label: Text(s.referButton),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: OutlinedButton.icon(onPressed: _openAssistant, icon: const Icon(Icons.assignment_outlined), label: Text(s.assistantShort))),
            ],
          ),
        ),
      ),
      children: [
        if (_busy) const LinearProgressIndicator(),
        switch (_state) {
          Loading<PatientRoute>() => Column(
              children: [
                if (preview != null) Align(alignment: Alignment.centerLeft, child: OrgName(preview.moName, prefix: '${s.waitingFor(preview.daysWaiting)} · ')),
                const SizedBox(height: AppSpacing.md),
                const Skeleton(height: 160, radius: AppRadius.md),
                const SizedBox(height: AppSpacing.lg),
                const KpiRowSkeleton(),
                const SizedBox(height: AppSpacing.lg),
                const ListSkeleton(),
              ],
            ),
          Failed<PatientRoute>(:final error) => switch (error) {
              ApiException(status: 403) => EmptyState(icon: Icons.lock_outline, title: s.forbiddenRegion),
              ApiException(status: 404) => EmptyState(icon: Icons.person_off_outlined, title: s.patientNotFound, body: widget.patientRef),
              _ => ErrorBox(error: error, onRetry: _load),
            },
          Loaded<PatientRoute>(:final data) => DoctorRouteView(route: data, busy: _busy, onRedirect: _redirect, onKeep: _keep),
        },
        if (route != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(s.routeSynthetic(dateShort(route.asOf)), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
        ],
      ],
    );
  }
}
