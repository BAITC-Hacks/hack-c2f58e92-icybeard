import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
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
import '../widgets/pill_filter.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// Журнал решений по доске M-Decisions: пилюли Все · Маршрут · Направление, группы по дням (label + карточка-список),
/// строка «реф 15/500 · Военный госпиталь → Достар Мед · время · «причина»» с чипом «совпало» (sage), если выбрана
/// рекомендованная, иначе «иначе»; тап — лист с полными именами, кодами и ключом записи. Имена организаций — из
/// справочника региона (журнал отдаёт только коды).
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

  /// «A → B», «Оставлен: A» при совпадении, «Направление: B» без рекомендации.
  String _line(S s, DecisionRecord r) {
    if (r.recommendedMoCode == null) {
      return s.referralLine(_shortName(r.chosenMoCode));
    }
    if (r.recommendedMoCode == r.chosenMoCode) {
      return s.keptLine(_shortName(r.chosenMoCode));
    }
    return '${_shortName(r.recommendedMoCode)} → ${_shortName(r.chosenMoCode)}';
  }

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
                children: [FieldLabel(label), SelectableText(value, style: theme.textTheme.row)],
              ),
            );
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.xxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(dateTimeShort(record.recordedAt), style: theme.textTheme.titleLarge?.merge(AppType.numeric))),
                  StatusChip(_subjectLabel(s, record.subject), tone: StatusTone.neutral),
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
    final colors = AppPalette.of(context);
    return PageScaffold(
      title: s.decisionsTitle,
      leading: const DarumenMark(size: 28),
      onRefresh: _load,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: PillFilter<String?>(
            items: [(null, s.subjectAll), ('route', s.subjectRoute), ('referral', s.subjectReferral)],
            selected: _subject,
            onChanged: (v) => setState(() => _subject = v),
          ),
        ),
        LoadStateView<List<DecisionRecord>>(
          state: _state,
          onRetry: _load,
          skeleton: const CardSkeleton(height: 300),
          isEmpty: (items) => !items.any((d) => _subject == null || d.subject == _subject),
          empty: EmptyState(icon: Icons.history, title: s.emptyDecisions),
          builder: (_, items) {
            final groups = groupByDay([for (final d in items) if (_subject == null || d.subject == _subject) d], (d) => d.recordedAt, s);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (g, group) in groups.indexed) ...[
                  Padding(
                    padding: EdgeInsets.fromLTRB(0, g == 0 ? AppSpacing.xs : AppSpacing.lg, 0, AppSpacing.sm),
                    child: Text(group.label.toUpperCase(), style: theme.textTheme.overline.copyWith(color: colors.muted)),
                  ),
                  AppCard(
                    padding: AppCard.list,
                    child: Column(
                      children: [
                        for (final (i, record) in group.items.indexed)
                          _DecisionRow(
                            record: record,
                            line: _line(s, record),
                            last: i == group.items.length - 1,
                            onTap: () => _openDetails(record),
                          ),
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

class _DecisionRow extends StatelessWidget {
  const _DecisionRow({required this.record, required this.line, required this.last, required this.onTap});

  final DecisionRecord record;
  final String line;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final matched = record.recommendedMoCode != null && record.recommendedMoCode == record.chosenMoCode;
    final detail = [timeShort(record.recordedAt), if (record.reason != null && record.reason!.isNotEmpty) '«${record.reason}»'].join(' · ');
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: AppSizes.row),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          decoration: last ? null : BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(record.subjectId ?? record.decisionId, style: theme.textTheme.rowStrong.merge(AppType.numeric), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(line, style: theme.textTheme.bodySmall?.copyWith(color: colors.ink, height: 1.35), maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(detail, style: theme.textTheme.rowDetail.copyWith(color: colors.faint).merge(AppType.numeric), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              StatusChip(matched ? s.matched : s.differed, tone: matched ? StatusTone.ok : StatusTone.neutral),
            ],
          ),
        ),
      ),
    );
  }
}
