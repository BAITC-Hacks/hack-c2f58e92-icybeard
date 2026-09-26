import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/day_groups.dart';
import '../widgets/empty_state.dart';
import '../widgets/format.dart';
import '../widgets/load_state_view.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// Журнал решений врача: чипы Все · Маршрут · Направление, группы по дням, строка «время · чип предмета ·
/// Военный госпиталь → Достар Мед · причина в кавычках»; тап — лист с полными именами, кодами и ключом записи.
/// Имена организаций — из справочника региона (журнал отдаёт только коды).
class DecisionsScreen extends StatefulWidget {
  const DecisionsScreen({super.key});

  @override
  State<DecisionsScreen> createState() => _DecisionsScreenState();
}

class _DecisionsScreenState extends State<DecisionsScreen> {
  LoadState<List<DecisionRecord>> _state = const Loading();
  Map<String, String> _orgNames = const {};
  String? _subject;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<Session>();
    setState(() => _state = const Loading());
    try {
      final results = await Future.wait<Object>([
        session.api.myDecisions(),
        session.api.organizations(session.region).catchError((_) => <Organization>[]),
      ]);
      if (mounted) {
        setState(() {
          _state = Loaded(results[0] as List<DecisionRecord>);
          _orgNames = {for (final o in results[1] as List<Organization>) o.moCode: o.name};
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  String _fullName(String? code) => code == null ? '—' : _orgNames[code] ?? code;

  String _shortName(String? code) => code == null ? '—' : shortOrgName(_fullName(code));

  void _openDetails(DecisionRecord record) {
    final s = S.at(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheet) {
        final theme = Theme.of(sheet);
        Widget row(String label, String value) => Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [Text(label, style: theme.textTheme.labelSmall), SelectableText(value, style: theme.textTheme.bodyMedium)],
              ),
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(dateTimeShort(record.recordedAt), style: theme.textTheme.titleMedium?.merge(AppType.numeric))),
                  StatusChip(_subjectLabel(s, record.subject), tone: record.subject == 'route' ? StatusTone.accent : StatusTone.neutral),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              row(s.recommendedLabel, '${_fullName(record.recommendedMoCode)}${record.recommendedMoCode == null ? '' : ' (${record.recommendedMoCode})'}'),
              row(s.chosenLabel, '${_fullName(record.chosenMoCode)}${record.chosenMoCode == null ? '' : ' (${record.chosenMoCode})'}'),
              if (record.subjectId != null) row(s.subjectIdLabel, record.subjectId!),
              if (record.reason != null && record.reason!.isNotEmpty) row(s.reasonShort, record.reason!),
              row(s.recordKeyLabel, record.decisionId),
            ],
          ),
        );
      },
    );
  }

  static String _subjectLabel(S s, String subject) => switch (subject) {
        'route' => s.subjectRoute,
        'referral' => s.subjectReferral,
        _ => subject,
      };

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    return PageScaffold(
      title: s.decisionsTitle,
      onRefresh: _load,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final (value, label) in [(null, s.subjectAll), ('route', s.subjectRoute), ('referral', s.subjectReferral)])
              ChoiceChip(label: Text(label), selected: _subject == value, onSelected: (_) => setState(() => _subject = value)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        LoadStateView<List<DecisionRecord>>(
          state: _state,
          onRetry: _load,
          skeleton: const ListSkeleton(count: 5, itemHeight: 72),
          isEmpty: (items) => !items.any((d) => _subject == null || d.subject == _subject),
          empty: EmptyState(icon: Icons.history, title: s.emptyDecisions),
          builder: (_, items) {
            final groups = groupByDay([for (final d in items) if (_subject == null || d.subject == _subject) d], (d) => d.recordedAt, s);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final group in groups) ...[
                  Padding(padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.sm), child: Text(group.label, style: theme.textTheme.labelSmall)),
                  Card(
                    child: Column(
                      children: [
                        for (final (i, record) in group.items.indexed) ...[
                          if (i > 0) const Divider(),
                          ListTile(
                            onTap: () => _openDetails(record),
                            title: Row(
                              children: [
                                Text(timeShort(record.recordedAt), style: theme.textTheme.labelSmall?.merge(AppType.numeric)),
                                const SizedBox(width: AppSpacing.sm),
                                StatusChip(_subjectLabel(s, record.subject), tone: record.subject == 'route' ? StatusTone.accent : StatusTone.neutral),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: AppSpacing.xs),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${_shortName(record.recommendedMoCode)} → ${_shortName(record.chosenMoCode)}', style: theme.textTheme.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                                  if (record.reason != null && record.reason!.isNotEmpty)
                                    Text('«${record.reason}»', style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
