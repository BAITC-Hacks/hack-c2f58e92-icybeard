import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../widgets/api_error.dart';
import '../widgets/app_card.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/decisions/decision_row.dart';
import '../widgets/decisions/decision_text.dart';
import '../widgets/empty_state.dart';
import '../widgets/format.dart';
import '../widgets/load_state_view.dart';
import '../widgets/pill_filter.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_view.dart';

/// Журнал решений врача (веб DecisionsView): мои решения, свежие первыми (до 200 записей, `actor=me`) — что
/// рекомендовала система, что выбрано и почему. Служебные записи скрайба скрыты (решение API 13). Сверху — подзаголовок
/// веба и пилюли предмета со счётчиками («Все решения · N», «Пациент в очереди · N», «Новое направление · N»); строка
/// — объект, что произошло (события маршрута — подписями журнала персонала, Q-8), дата и время, итог словами и
/// причина; тап — лист подробностей без номера записи. Имена организаций, регионов и профилей — из справочников;
/// чего там нет, показывается кодом. CSV, период, роль и показатели — только в вебе (§6.4).
class DecisionsScreen extends StatefulWidget {
  const DecisionsScreen({super.key});

  @override
  State<DecisionsScreen> createState() => _DecisionsScreenState();
}

class _DecisionsScreenState extends State<DecisionsScreen> {
  /// Порядок предметов в пилюлях (как в выпадающем списке веба); незнакомые предметы — после них.
  static const _subjectOrder = [DecisionCodes.subjectReferral, DecisionCodes.subjectRoute, DecisionCodes.subjectAnomaly];

  LoadState<List<DecisionRecord>> _state = const Loading();
  DecisionNames _names = const DecisionNames();
  String? _subject;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  /// Первая загрузка — скелетон; обновление жестом оставляет список на экране, ошибка обновления — в снекбаре.
  Future<void> _load() async {
    final session = context.read<Session>();
    final hadData = _state is Loaded<List<DecisionRecord>>;
    if (!hadData) setState(() => _state = const Loading());
    try {
      final results = await Future.wait<Object>([session.api.myDecisions(size: 200), _loadNames(session)]);
      if (!mounted) return;
      setState(() {
        _state = Loaded(journalDecisions(results[0] as List<DecisionRecord>));
        _names = results[1] as DecisionNames;
      });
    } on Object catch (e) {
      if (!mounted) return;
      if (hadData) {
        await showApiError(context, e);
      } else {
        setState(() => _state = Failed(e));
      }
    }
  }

  /// Справочники для подписей. Они — украшение: без них журнал показывает коды, поэтому сбой справочника не
  /// превращается в ошибку экрана, а оставляет пустой словарь (код вместо имени виден врачу).
  static Future<DecisionNames> _loadNames(Session session) async {
    final api = session.api;
    final results = await Future.wait<Object>([
      _orEmpty<Region>(api.regions()),
      _orEmpty<BedProfile>(api.profiles()),
      _orEmpty<Organization>(api.organizations(session.region)),
    ]);
    return DecisionNames(
      regions: {for (final r in results[0] as List<Region>) r.kato: r.name},
      profiles: {for (final p in results[1] as List<BedProfile>) p.code: p.name},
      organizations: {for (final o in results[2] as List<Organization>) o.moCode: o.name},
    );
  }

  static Future<List<T>> _orEmpty<T>(Future<List<T>> request) => request.catchError((Object _) => <T>[], test: (e) => e is Exception);

  List<String> _subjects(List<DecisionRecord> items) {
    final present = {for (final d in items) d.subject};
    return [
      for (final subject in _subjectOrder)
        if (present.contains(subject)) subject,
      for (final subject in present)
        if (!_subjectOrder.contains(subject)) subject,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return PageScaffold(
      title: s.decisionsTitle,
      leading: const DarumenMark(size: 28),
      onRefresh: _load,
      children: [
        Text(s.decisionsLead, style: Theme.of(context).textTheme.bodySmall),
        LoadStateView<List<DecisionRecord>>(
          state: _state,
          onRetry: _load,
          skeleton: const CardSkeleton(height: 300),
          isEmpty: (items) => items.isEmpty,
          empty: EmptyState(icon: Icons.history, title: s.decisionsEmpty, body: s.decisionsEmptyText),
          builder: (_, items) => _list(s, items),
        ),
      ],
    );
  }

  Widget _list(S s, List<DecisionRecord> items) {
    final visible = [for (final d in items) if (_subject == null || d.subject == _subject) d];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: PillFilter<String?>(
            items: [
              (null, '${s.decisionsAll} · ${items.length}'),
              for (final subject in _subjects(items))
                (subject, '${capitalizeFirst(s.decisionsSubject(subject))} · ${items.where((d) => d.subject == subject).length}'),
            ],
            selected: _subject,
            onChanged: (value) => setState(() => _subject = value),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (visible.isEmpty)
          FilteredEmptyState(onReset: () => setState(() => _subject = null))
        else
          AppCard(
            padding: AppCard.list,
            child: Column(
              children: [
                for (final (i, record) in visible.indexed)
                  DecisionRow(
                    record: record,
                    names: _names,
                    last: i == visible.length - 1,
                    onTap: () => showDecisionSheet(context, record, _names),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
