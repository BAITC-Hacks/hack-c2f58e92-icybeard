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

/// «Мой путь» гражданина по доске M-Route: hero-карточка «Этап k из 5 · до N дн.», карточка этапов, ответ врача
/// карточкой-сигналом и кнопка «Понятно» внизу (запоминается в сессии), свёрнутые секции. Двусторонний маршрут:
/// «Вы ещё ждёте?» и «Попросить» шлют сигнал врачу с одним Idempotency-Key на нажатие.
class RouteScreen extends StatefulWidget {
  const RouteScreen({super.key});

  @override
  State<RouteScreen> createState() => _RouteScreenState();
}

class _RouteScreenState extends State<RouteScreen> {
  LoadState<PatientRoute> _state = const Loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<Session>();
    setState(() => _state = const Loading());
    try {
      final route = await session.api.myRoute(regionKato: session.regionFromAccount ? null : session.region);
      if (mounted) {
        setState(() => _state = Loaded(route));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  Future<void> _signal(String kind, {String? toMoCode, String? comment}) async {
    final session = context.read<Session>();
    final s = S.at(context);
    try {
      await session.api.sendRouteSignal(
        kind,
        toMoCode: toMoCode,
        comment: comment,
        idempotencyKey: newIdempotencyKey(),
        regionKato: session.regionFromAccount ? null : session.region,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toMoCode == null ? s.signalSent : s.requestSent)));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.serverUnavailable(e))));
      }
    }
  }

  Future<void> _request(Alternative alternative) async {
    final s = S.at(context);
    final comment = await RedirectReasonDialog.show(
      context,
      organization: alternative.name,
      subtitle: s.requestTitle(''),
      label: s.requestCommentLabel,
      confirmLabel: s.requestSend,
      optional: true,
    );
    if (comment == null || !mounted) {
      return;
    }
    await _signal(RouteCodes.requestRedirect, toMoCode: alternative.moCode, comment: comment);
  }

  /// По карточке-сигналу — «Сколько ждут» с профилем маршрута, где предложенная организация выделена.
  void _openWait(PatientRoute route) =>
      context.go('/home/wait?region=${Uri.encodeComponent(route.regionKato)}&profile=${Uri.encodeComponent(route.organization.profileCode)}');

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final session = context.watch<Session>();
    final route = switch (_state) { Loaded<PatientRoute>(:final data) => data, _ => null };
    final answer = route?.latestDecision;
    final unseen = answer != null && answer.decisionId != session.seenDecisionId;
    return PageScaffold(
      title: s.routeTitle,
      onRefresh: _load,
      bottom: unseen ? FilledButton(onPressed: () => session.markDecisionSeen(answer.decisionId), child: Text(s.gotIt)) : null,
      children: [
        LoadStateView<PatientRoute>(
          state: _state,
          onRetry: _load,
          skeleton: const Column(
            children: [
              CardSkeleton(height: 220),
              SizedBox(height: AppSpacing.md),
              CardSkeleton(height: 300),
            ],
          ),
          builder: (_, route) => RouteView(
            route: route,
            onSignal: (kind) => _signal(kind),
            onRequest: _request,
            seenDecisionId: session.seenDecisionId,
            onOpenAnswer: () => _openWait(route),
          ),
        ),
      ],
    );
  }
}
