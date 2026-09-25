import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/load_state_view.dart';
import '../widgets/redirect_reason_dialog.dart';
import '../widgets/route_view.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';

/// «Мой путь» гражданина: стадия по Стандарту, прогноз, анализы, где быстрее, решения врача, история.
/// Двусторонний маршрут: карточка «Вы ещё ждёте?» и «Попросить» у альтернатив шлют сигнал врачу (один
/// Idempotency-Key на нажатие). Гость видит приглашение войти, а не редирект.
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
    if (!session.isAuthenticated) {
      return;
    }
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
      organization: s.requestTitle(alternative.name),
      label: s.requestCommentLabel,
      confirmLabel: s.requestSend,
      optional: true,
    );
    if (comment == null || !mounted) {
      return;
    }
    await _signal(RouteCodes.requestRedirect, toMoCode: alternative.moCode, comment: comment);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final session = context.watch<Session>();
    if (!session.isAuthenticated) {
      return PageScaffold(
        title: s.routeTitle,
        children: [
          EmptyState(
            icon: Icons.lock_outline,
            title: s.loginRequiredTitle,
            body: s.loginRequiredBody,
            action: FilledButton(onPressed: () => context.go('/login?from=%2Fhome%2Froute'), child: Text(s.loginButton)),
          ),
        ],
      );
    }
    return PageScaffold(
      title: s.routeTitle,
      onRefresh: _load,
      children: [
        LoadStateView<PatientRoute>(
          state: _state,
          onRetry: _load,
          skeleton: const Column(
            children: [
              Skeleton(height: 96, radius: AppRadius.md),
              SizedBox(height: AppSpacing.lg),
              KpiRowSkeleton(),
              SizedBox(height: AppSpacing.lg),
              ListSkeleton(),
            ],
          ),
          builder: (_, route) => RouteView(route: route, onSignal: (kind) => _signal(kind), onRequest: _request),
        ),
      ],
    );
  }
}
