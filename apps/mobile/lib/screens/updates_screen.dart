import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/day_groups.dart';
import '../widgets/empty_state.dart';
import '../widgets/load_state_view.dart';
import '../widgets/route_events.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';

/// Уведомления — только события маршрута (как Messages в NHS App), группами по дням: Сегодня · Вчера · 22 сентября.
/// Строка: иконка типа (этап / врач / вы), заголовок в одну строку с коротким именем, подстрока — причина в
/// кавычках или этап; у предложения врача — «Открыть маршрут». Push через eGov mobile — после интеграции.
class UpdatesScreen extends StatefulWidget {
  const UpdatesScreen({super.key});

  @override
  State<UpdatesScreen> createState() => _UpdatesScreenState();
}

class _UpdatesScreenState extends State<UpdatesScreen> {
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

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final session = context.watch<Session>();
    final theme = Theme.of(context);
    if (!session.isAuthenticated) {
      return PageScaffold(
        title: s.updatesTitle,
        children: [
          EmptyState(
            icon: Icons.notifications_none,
            title: s.updatesEmptyTitle,
            body: s.updatesEmptyBody,
            action: FilledButton(onPressed: () => context.go('/login?from=%2Fupdates'), child: Text(s.loginButton)),
          ),
          Text(s.updatesPushRoadmap, style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
        ],
      );
    }
    return PageScaffold(
      title: s.updatesTitle,
      onRefresh: _load,
      children: [
        LoadStateView<PatientRoute>(
          state: _state,
          onRetry: _load,
          skeleton: const ListSkeleton(count: 6),
          builder: (_, route) {
            final groups = groupByDay(routeEvents(route, s), (e) => e.at, s);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (groups.isEmpty)
                  EmptyState(icon: Icons.notifications_none, title: s.updatesEmptyTitle, body: s.updatesEmptyBody)
                else
                  for (final group in groups) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm),
                      child: Text(group.label, style: theme.textTheme.labelSmall),
                    ),
                    Card(
                      child: Column(
                        children: [
                          for (final (i, event) in group.items.indexed) ...[
                            if (i > 0) const Divider(),
                            _EventRow(event: event),
                          ],
                        ],
                      ),
                    ),
                  ],
                const SizedBox(height: AppSpacing.lg),
                Text(s.updatesPushRoadmap, style: theme.textTheme.labelSmall),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final RouteEvent event;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(event.icon, color: event.kind == RouteEventKind.checklist ? colors.muted : colors.accent),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (event.detail != null && event.detail!.isNotEmpty)
                  Text(event.detail!, style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (event.opensRoute)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36), tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      onPressed: () => context.go('/home/route'),
                      child: Text(s.openRoute),
                    ),
                  )
                else
                  const SizedBox(height: AppSpacing.xs),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
