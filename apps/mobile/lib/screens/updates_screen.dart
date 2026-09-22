import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/empty_state.dart';
import '../widgets/format.dart';
import '../widgets/load_state_view.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';

/// Уведомления — только события маршрута (как Messages в NHS App: ничего нерелевантного, никаких новостей).
/// Лента выводится на клиенте из пройденных стадий и решений врача; push через eGov mobile — после интеграции.
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

  List<_Event> _events(PatientRoute route, S s) {
    final events = <_Event>[
      for (final stage in route.timeline)
        if (stage.date != null && stage.status != RouteCodes.upcoming) _Event(stage.date!, stage.title, Icons.flag_outlined),
      for (final decision in route.decisions)
        _Event(
          decision.recordedAt,
          decision.kind == RouteCodes.redirect ? s.doctorProposed(decision.toMoName) : s.doctorKept,
          Icons.alt_route,
          detail: decision.reason,
        ),
    ];
    events.sort((a, b) => b.at.compareTo(a.at));
    return events;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final session = context.watch<Session>();
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
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
          skeleton: const ListSkeleton(),
          builder: (_, route) {
            final events = _events(route, s);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (events.isEmpty)
                  EmptyState(icon: Icons.notifications_none, title: s.updatesEmptyTitle, body: s.updatesEmptyBody)
                else
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < events.length; i++) ...[
                          if (i > 0) const Divider(),
                          ListTile(
                            leading: Icon(events[i].icon, color: colors.accent),
                            title: Text(events[i].title),
                            subtitle: Text(
                              [dateShort(events[i].at), if (events[i].detail != null && events[i].detail!.isNotEmpty) events[i].detail!].join(' · '),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
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

class _Event {
  const _Event(this.at, this.title, this.icon, {this.detail});

  final String at;
  final String title;
  final IconData icon;
  final String? detail;
}
