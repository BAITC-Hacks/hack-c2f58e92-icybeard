import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/empty_state.dart';
import '../widgets/format.dart';
import '../widgets/load_state_view.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// Врач: журнал собственных решений по направлениям и маршрутам (GET /api/v1/journal/decisions?actor=me).
class DecisionsScreen extends StatefulWidget {
  const DecisionsScreen({super.key});

  @override
  State<DecisionsScreen> createState() => _DecisionsScreenState();
}

class _DecisionsScreenState extends State<DecisionsScreen> {
  LoadState<List<DecisionRecord>> _state = const Loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const Loading());
    try {
      final items = await context.read<Session>().api.myDecisions();
      if (mounted) {
        setState(() => _state = Loaded(items));
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
    return PageScaffold(
      title: s.decisionsTitle,
      onRefresh: _load,
      children: [
        LoadStateView<List<DecisionRecord>>(
          state: _state,
          onRetry: _load,
          skeleton: const ListSkeleton(count: 5, itemHeight: 80),
          isEmpty: (items) => items.isEmpty,
          empty: EmptyState(icon: Icons.history, title: s.emptyDecisions),
          builder: (_, items) => Card(
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    title: Row(
                      children: [
                        Expanded(child: Text(dateTimeShort(items[i].recordedAt), style: theme.textTheme.bodySmall?.merge(AppType.numeric))),
                        StatusChip(_subject(s, items[i].subject), tone: items[i].subject == 'route' ? StatusTone.accent : StatusTone.neutral),
                      ],
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.xs),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.recommendedChosen(items[i].recommendedMoCode, items[i].chosenMoCode), style: theme.textTheme.bodyMedium?.merge(AppType.numeric)),
                          if (items[i].subjectId != null) Text(items[i].subjectId!, style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
                          if (items[i].reason != null && items[i].reason!.isNotEmpty) Text(s.reasonPrefix(items[i].reason!), style: theme.textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _subject(S s, String subject) => switch (subject) {
        'route' => s.patientRouteTitle,
        'referral' => s.referralLabel,
        _ => subject,
      };
}
