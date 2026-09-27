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
import '../widgets/redirect_reason_dialog.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';

/// Маршрут пациента для врача по доске M-Patient: реф крупно, подпись «профиль · ждёт N дн. · приоритет P»,
/// карточка «Рекомендация» с hero «≈ N дн.» лучшей альтернативы, риском отказа и запросом пациента, список
/// альтернатив (тап — перенаправить с причиной), свёрнутые секции; внизу «Открыть направление» (ассистент) и
/// «AI-скрайб». Перенаправление и «Оставить» пишутся одним Idempotency-Key на нажатие; после записи маршрут
/// перечитывается. Риск отказа показывается только врачу.
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
    final text = reason ??
        await RedirectReasonDialog.show(
          context,
          organization: alternative.name,
          subtitle: '≈ ${days(alternative.p50Days)} ${s.daysUnit} · ${s.riskShort(pct(alternative.pRefusal))}',
        );
    if (text == null || text.isEmpty || !mounted) {
      return;
    }
    await _record(() => context.read<Session>().api.redirectRoute(widget.patientRef, toMoCode: alternative.moCode, reason: text, idempotencyKey: newIdempotencyKey()), s.redirectDone);
  }

  Future<void> _keep(String reason) async {
    final s = S.at(context);
    await _record(() => context.read<Session>().api.keepRoute(widget.patientRef, reason: reason, idempotencyKey: newIdempotencyKey()), s.keepDone);
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

  String get _ref => Uri.encodeComponent(widget.patientRef);

  void _openAssistant() {
    final route = _route;
    final preview = widget.preview;
    final moCode = route?.organization.moCode ?? preview?.moCode ?? '';
    final profile = route?.organization.profileCode ?? preview?.profileCode ?? '';
    context.go('/doctor/patients/$_ref/referral?moCode=$moCode&profileCode=$profile');
  }

  void _openScribe() => context.go('/doctor/patients/$_ref/scribe');

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final preview = widget.preview;
    final route = _route;
    return PageScaffold(
      title: s.patientRouteTitle,
      onRefresh: _load,
      bottom: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(onPressed: _busy ? null : _openAssistant, child: Text(s.openReferral)),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(onPressed: _openScribe, icon: const Icon(Icons.mic_none, size: 20), label: Text(s.scribeTitle)),
        ],
      ),
      children: [
        if (_busy) const LinearProgressIndicator(),
        switch (_state) {
          Loading<PatientRoute>() => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.patientRef, style: theme.textTheme.headlineSmall?.merge(AppType.numeric)),
                if (preview != null) Text('${s.waitingFor(preview.daysWaiting)} · ${shortOrgName(preview.moName)}', style: theme.textTheme.bodySmall),
                const SizedBox(height: AppSpacing.md),
                const CardSkeleton(height: 220),
                const SizedBox(height: AppSpacing.md),
                const CardSkeleton(height: 160),
              ],
            ),
          Failed<PatientRoute>(:final error) => switch (error) {
              ApiException(status: 403) => EmptyState(icon: Icons.lock_outline, title: s.forbiddenRegion),
              ApiException(status: 404) => EmptyState(icon: Icons.person_off_outlined, title: s.patientNotFound, body: widget.patientRef),
              _ => ErrorBox(error: error, onRetry: _load),
            },
          Loaded<PatientRoute>(:final data) => DoctorRouteView(route: data, busy: _busy, onRedirect: _redirect, onKeep: _keep),
        },
        if (route != null) Text(s.routeSynthetic(dateShort(route.asOf)), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
      ],
    );
  }
}
