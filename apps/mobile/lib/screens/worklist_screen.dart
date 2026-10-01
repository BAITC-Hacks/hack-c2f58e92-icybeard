import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/circle_button.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/empty_state.dart';
import '../widgets/format.dart';
import '../widgets/load_state_view.dart';
import '../widgets/origin_tag.dart';
import '../widgets/pill_filter.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_view.dart';
import '../widgets/status_chip.dart';

/// «Пациенты» врача по доске M-Worklist: пилюли «Сегодня» (есть флаги или сигнал пациента) / «Все», регион справа,
/// круглая кнопка поиска по номеру пациента, строки «реф 17/500 · ждёт N дн. · организация» с чипом статуса
/// справа (риск отказа и запрос пациента — янтарные, есть быстрее — зелёный, иначе «ожидает решения»).
/// Сортировка по приоритету модели; ответ на запрос пациента — на экране маршрута.
class WorklistScreen extends StatefulWidget {
  const WorklistScreen({super.key});

  @override
  State<WorklistScreen> createState() => _WorklistScreenState();
}

class _WorklistScreenState extends State<WorklistScreen> {
  LoadState<WorklistResponse> _state = const Loading();
  List<Region> _regions = const [];
  bool _today = true;
  bool _searching = false;
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _loadRegions();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _state = const Loading());
    try {
      final page = await context.read<Session>().api.worklistPage();
      if (mounted) {
        setState(() => _state = Loaded(page));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  Future<void> _loadRegions() async {
    try {
      final regions = await context.read<Session>().api.regions();
      if (mounted) {
        setState(() => _regions = regions);
      }
    } catch (_) {
      // регион покажем кодом
    }
  }

  void _toggleSearch() => setState(() {
        _searching = !_searching;
        if (!_searching) {
          _query.clear();
        }
      });

  static bool needsAttention(WorklistItem item) => item.riskFlags.isNotEmpty || item.patientSignal != null;

  List<WorklistItem> _visible(List<WorklistItem> items) {
    final q = _query.text.trim().toLowerCase();
    final filtered = [
      for (final i in items)
        if ((!_today || needsAttention(i)) && (q.isEmpty || i.patientRef.toLowerCase().contains(q))) i,
    ];
    filtered.sort((a, b) => b.priority.compareTo(a.priority));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final session = context.watch<Session>();
    final regionName = _regions.where((r) => r.kato == session.region).map((r) => r.name).firstOrNull ?? session.region;
    return PageScaffold(
      leading: const HomeMarkAnchor(),
      title: s.worklistTitle,
      actions: [CircleIconButton(icon: _searching ? Icons.close : Icons.search, label: s.searchPatient, onTap: _toggleSearch)],
      onRefresh: _load,
      children: [
        Row(
          children: [
            PillFilter<bool>(items: [(true, s.filterToday), (false, s.filterAll)], selected: _today, onChanged: (v) => setState(() => _today = v)),
            const Spacer(),
            Flexible(child: Text(regionName, style: theme.textTheme.labelSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
          ],
        ),
        if (_searching)
          TextField(
            controller: _query,
            autofocus: true,
            autocorrect: false,
            textCapitalization: TextCapitalization.characters,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(hintText: s.searchByRefHint, prefixIcon: const Icon(Icons.search)),
          ),
        LoadStateView<WorklistResponse>(
          state: _state,
          onRetry: _load,
          skeleton: const CardSkeleton(height: 320),
          builder: (_, page) {
            final visible = _visible(page.items);
            final stale = StaleDataBanner.isStale(page.asOf);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // MOBILE-REFACTOR-SHIM (F2a): у StaleDataBanner больше нет onRefresh («Обновить →» снят, как в вебе); D1 проверяет строку при переделке экрана
                if (stale) ...[StaleDataBanner(asOf: page.asOf), const SizedBox(height: AppSpacing.md)],
                if (page.items.isEmpty)
                  EmptyState(icon: Icons.people_outline, title: s.worklistNoPatients, body: s.worklistNoPatientsBody)
                else if (visible.isEmpty)
                  FilteredEmptyState(
                    body: _today && _query.text.isEmpty ? s.worklistTodayEmpty : s.stateFilterBody,
                    resetLabel: _today && _query.text.isEmpty ? s.showAll : s.resetFilters,
                    onReset: () => setState(() {
                      _today = false;
                      _query.clear();
                    }),
                  )
                else
                  AppCard(
                    padding: AppCard.list,
                    child: Column(
                      children: [
                        for (final (i, item) in visible.indexed)
                          _PatientRow(
                            item: item,
                            last: i == visible.length - 1,
                            onOpen: () => context.go('/doctor/patients/${Uri.encodeComponent(item.patientRef)}', extra: item),
                          ),
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    OriginTag(page.modelBacked ? Origin.ml : Origin.formula),
                    const SizedBox(width: 10),
                    if (!stale) Expanded(child: Text(s.asOfLabel(dateShort(page.asOf)), style: theme.textTheme.labelSmall?.merge(AppType.numeric))),
                  ],
                ),
                if (!page.modelBacked) ...[const SizedBox(height: AppSpacing.xs), Text(s.modelUnavailableNote, style: theme.textTheme.labelSmall)],
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Строка пациента: реф 17/500 табличными цифрами, «ждёт N дн. · организация» 14 ink-2, чип статуса справа.
class _PatientRow extends StatelessWidget {
  const _PatientRow({required this.item, required this.last, required this.onOpen});

  final WorklistItem item;
  final bool last;
  final VoidCallback onOpen;

  (String, StatusTone) _status(S s) {
    if (item.patientSignal != null || item.riskFlags.contains(RouteCodes.patientSignalFlag)) {
      return (s.statusSignal, StatusTone.warn);
    }
    if (item.riskFlags.contains('refusal_risk')) {
      return (s.statusRisk, StatusTone.warn);
    }
    if (item.riskFlags.contains('faster_alternative')) {
      return (s.statusFaster, StatusTone.ok);
    }
    return (s.statusAwaiting, StatusTone.neutral);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final (label, tone) = _status(s);
    return Semantics(
      button: true,
      label: '${item.patientRef}, ${s.waitingFor(item.daysWaiting)}, $label',
      child: InkWell(
        onTap: onOpen,
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
                    Text(item.patientRef, style: theme.textTheme.titleMedium?.merge(AppType.numeric)),
                    const SizedBox(height: 2),
                    Text(
                      '${s.waitingFor(item.daysWaiting)} · ${shortOrgName(item.moName)}',
                      style: theme.textTheme.bodySmall?.copyWith(color: colors.muted).merge(AppType.numeric),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              StatusChip(label, tone: tone),
            ],
          ),
        ),
      ),
    );
  }
}
