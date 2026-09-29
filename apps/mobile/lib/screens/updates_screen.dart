import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/service_status_notifier.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/day_groups.dart';
import '../widgets/empty_state.dart';
import '../widgets/format.dart';
import '../widgets/load_state_view.dart';
import '../widgets/notice_card.dart';
import '../widgets/route_events.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';

/// Уведомления по доске M-Updates — только события маршрута (как Messages в NHS App) внутри одной карточки,
/// группами по дням: label «Сегодня · Вчера · 22 сентября», строки 56 px с синей точкой у нового, заголовком 14,
/// подстрокой 13 и временем справа; предложение врача открывает маршрут. Пока push-сервис не подключён
/// (`GET /public/service-status`), внизу честная подпись: push не приходят, новые события — здесь.
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
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final seen = context.select<Session, String?>((x) => x.seenDecisionId);
    final push = ServiceStatusNotifier.watch(context).push;
    return PageScaffold(
      title: s.updatesTitle,
      leading: const DarumenMark(size: 28),
      onRefresh: _load,
      children: [
        LoadStateView<PatientRoute>(
          state: _state,
          onRetry: _load,
          skeleton: const CardSkeleton(height: 360),
          builder: (_, route) {
            final groups = groupByDay(routeEvents(route, s, seenDecisionId: seen), (e) => e.at, s);
            if (groups.isEmpty) {
              return EmptyState(icon: Icons.notifications_none, title: s.updatesEmptyTitle, body: s.updatesEmptyBody);
            }
            return AppCard(
              padding: AppCard.list,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final (g, group) in groups.indexed) ...[
                    Padding(
                      padding: EdgeInsets.fromLTRB(0, g == 0 ? AppSpacing.md : AppSpacing.lg, 0, AppSpacing.xs),
                      child: Text(group.label.toUpperCase(), style: theme.textTheme.overline.copyWith(color: colors.muted)),
                    ),
                    for (final (i, event) in group.items.indexed)
                      ListRow(
                        dot: event.isNew,
                        strong: event.isNew,
                        title: event.title,
                        subtitle: event.detail,
                        last: g == groups.length - 1 && i == group.items.length - 1,
                        trailing: Text(timeShort(event.at), style: theme.textTheme.labelSmall?.copyWith(color: colors.muted).merge(AppType.numeric)),
                        onTap: event.opensRoute ? () => context.go('/home/route') : null,
                      ),
                  ],
                ],
              ),
            );
          },
        ),
        if (!push.isUp) NoticeCard(icon: Icons.info_outline, body: s.pushDownNote(push.reason)),
      ],
    );
  }
}
