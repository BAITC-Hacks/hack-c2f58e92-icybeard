import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../widgets/load_state_view.dart';
import '../widgets/redirect_reason_dialog.dart';
import '../widgets/route_view.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';

/// Маршрут пациента для врача: тот же RouteView с панелью врача и кнопкой «Направить сюда» у альтернатив.
/// Перенаправление пишется одним Idempotency-Key на нажатие; после записи маршрут перечитывается.
class PatientRouteScreen extends StatefulWidget {
  const PatientRouteScreen({super.key, required this.patientRef, this.preview});

  final String patientRef;
  final WorklistItem? preview;

  @override
  State<PatientRouteScreen> createState() => _PatientRouteScreenState();
}

class _PatientRouteScreenState extends State<PatientRouteScreen> {
  LoadState<PatientRoute> _state = const Loading();
  bool _redirecting = false;

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

  Future<void> _redirect(Alternative alternative) async {
    final s = S.at(context);
    final reason = await RedirectReasonDialog.show(context, organization: alternative.name);
    if (reason == null || reason.isEmpty || !mounted) {
      return;
    }
    await _record(() => context.read<Session>().api.redirectRoute(widget.patientRef, toMoCode: alternative.moCode, reason: reason, idempotencyKey: newIdempotencyKey()), s.redirectDone);
  }

  /// «Оставить» с причиной — ответ на сигнал пациента, в журнале Kind = keep.
  Future<void> _keep() async {
    final s = S.at(context);
    final reason = await RedirectReasonDialog.show(context, organization: s.keepHere, label: s.keepReasonLabel, confirmLabel: s.keepHere);
    if (reason == null || reason.isEmpty || !mounted) {
      return;
    }
    await _record(() => context.read<Session>().api.keepRoute(widget.patientRef, reason: reason, idempotencyKey: newIdempotencyKey()), s.keepDone);
  }

  Future<void> _record(Future<String> Function() call, String done) async {
    final s = S.at(context);
    setState(() => _redirecting = true);
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
        setState(() => _redirecting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final preview = widget.preview;
    return PageScaffold(
      title: widget.patientRef,
      onRefresh: _load,
      bottom: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.md),
          child: OutlinedButton.icon(
            onPressed: () {
              final route = switch (_state) { Loaded<PatientRoute>(:final data) => data, _ => null };
              final moCode = route?.organization.moCode ?? preview?.moCode ?? '';
              final profile = route?.organization.profileCode ?? preview?.profileCode ?? '';
              context.go('/doctor/patients/${Uri.encodeComponent(widget.patientRef)}/referral?moCode=$moCode&profileCode=$profile');
            },
            icon: const Icon(Icons.assignment_outlined),
            label: Text(s.openReferralAssistant),
          ),
        ),
      ),
      children: [
        if (_redirecting) const LinearProgressIndicator(),
        LoadStateView<PatientRoute>(
          state: _state,
          onRetry: _load,
          skeleton: Column(
            children: [
              if (preview != null) Text('${preview.moName} · ${s.waitingFor(preview.daysWaiting)}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.md),
              const Skeleton(height: 120, radius: AppRadius.md),
              const SizedBox(height: AppSpacing.lg),
              const KpiRowSkeleton(),
              const SizedBox(height: AppSpacing.lg),
              const ListSkeleton(),
            ],
          ),
          builder: (_, route) => RouteView(route: route, doctorMode: true, onRedirect: _redirecting ? null : _redirect, onKeep: _redirecting ? null : _keep),
        ),
      ],
    );
  }
}
