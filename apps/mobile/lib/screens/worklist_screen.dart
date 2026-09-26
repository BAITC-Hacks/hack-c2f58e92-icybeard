import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import '../widgets/empty_state.dart';
import '../widgets/format.dart';
import '../widgets/load_state_view.dart';
import '../widgets/org_name.dart';
import '../widgets/origin_tag.dart';
import '../widgets/redirect_reason_dialog.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

enum _Sort { priority, days }

/// «Пациенты» врача: заголовок с регионом и датой данных [ML], ряд плиток-счётчиков как фильтр (считаются на
/// клиенте по полному списку), сортировка приоритет / дни, плотные строки с коротким именем организации и
/// коротким следующим шагом; строка с запросом пациента — акцентная полоса и «Направить сюда» / «Оставить».
class WorklistScreen extends StatefulWidget {
  const WorklistScreen({super.key});

  @override
  State<WorklistScreen> createState() => _WorklistScreenState();
}

class _WorklistScreenState extends State<WorklistScreen> {
  static const _flags = [null, RouteCodes.patientSignalFlag, 'stuck_over_30', 'refusal_risk', 'faster_alternative'];

  LoadState<WorklistResponse> _state = const Loading();
  List<Region> _regions = const [];
  String? _flag;
  _Sort _sort = _Sort.priority;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadRegions();
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

  /// Ответ на сигнал прямо из списка: «Направить сюда» в просимую организацию или «Оставить», оба с причиной.
  Future<void> _answer(WorklistItem item, {required bool redirect}) async {
    final s = S.at(context);
    final signal = item.patientSignal!;
    final reason = await (redirect
        ? RedirectReasonDialog.show(context, organization: signal.toMoName ?? signal.toMoCode ?? '', subtitle: item.patientRef)
        : RedirectReasonDialog.show(context, organization: s.keepHere, subtitle: item.patientRef, label: s.keepReasonLabel, confirmLabel: s.keepHere));
    if (reason == null || reason.isEmpty || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final api = context.read<Session>().api;
      if (redirect) {
        await api.redirectRoute(item.patientRef, toMoCode: signal.toMoCode!, reason: reason, idempotencyKey: newIdempotencyKey());
      } else {
        await api.keepRoute(item.patientRef, reason: reason, idempotencyKey: newIdempotencyKey());
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(redirect ? s.redirectDone : s.keepDone)));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.serverUnavailable(e))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  List<WorklistItem> _visible(List<WorklistItem> items) {
    final filtered = _flag == null ? [...items] : [for (final i in items) if (i.riskFlags.contains(_flag)) i];
    filtered.sort((a, b) => _sort == _Sort.priority ? b.priority.compareTo(a.priority) : b.daysWaiting.compareTo(a.daysWaiting));
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final session = context.watch<Session>();
    final regionName = _regions.where((r) => r.kato == session.region).map((r) => r.name).firstOrNull ?? session.region;
    return PageScaffold(
      title: s.patientsTitle(regionName),
      actions: [
        PopupMenuButton<_Sort>(
          icon: const Icon(Icons.swap_vert),
          tooltip: s.sortLabel,
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (_) => [
            CheckedPopupMenuItem(value: _Sort.priority, checked: _sort == _Sort.priority, child: Text(s.sortByPriority)),
            CheckedPopupMenuItem(value: _Sort.days, checked: _sort == _Sort.days, child: Text(s.sortByDays)),
          ],
        ),
      ],
      onRefresh: _load,
      children: [
        LoadStateView<WorklistResponse>(
          state: _state,
          onRetry: _load,
          skeleton: const Column(children: [Skeleton(height: 64, radius: AppRadius.md), SizedBox(height: AppSpacing.md), ListSkeleton(count: 5, itemHeight: 120)]),
          builder: (_, page) {
            final visible = _visible(page.items);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(s.asOfLabel(dateShort(page.asOf)), style: theme.textTheme.labelSmall)),
                    OriginTag(page.modelBacked ? Origin.ml : Origin.formula),
                  ],
                ),
                if (!page.modelBacked) ...[const SizedBox(height: AppSpacing.xs), Text(s.modelUnavailableNote, style: theme.textTheme.labelSmall)],
                const SizedBox(height: AppSpacing.md),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final flag in _flags) ...[
                        _CounterTile(
                          label: s.flagShort(flag),
                          count: flag == null ? page.items.length : page.items.where((i) => i.riskFlags.contains(flag)).length,
                          selected: _flag == flag,
                          onTap: () => setState(() => _flag = flag),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (visible.isEmpty)
                  EmptyState(
                    icon: Icons.people_outline,
                    title: s.worklistEmpty,
                    action: OutlinedButton(onPressed: () => setState(() => _flag = null), child: Text(s.showAll)),
                  )
                else
                  for (final item in visible)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: _PatientRow(
                        item: item,
                        busy: _busy,
                        onOpen: () => context.go('/doctor/patients/${Uri.encodeComponent(item.patientRef)}', extra: item),
                        onAnswer: (redirect) => _answer(item, redirect: redirect),
                      ),
                    ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Плитка-счётчик: число и подпись; выбранная — акцентная рамка. Это и есть фильтр.
class _CounterTile extends StatelessWidget {
  const _CounterTile({required this.label, required this.count, required this.selected, required this.onTap});

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '$label $count',
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? colors.accentSoft : colors.card,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: selected ? colors.accent : colors.hairline),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$count', style: theme.textTheme.titleMedium?.merge(AppType.numeric).copyWith(color: selected ? colors.accent : colors.ink)),
              Text(label, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _PatientRow extends StatelessWidget {
  const _PatientRow({required this.item, required this.busy, required this.onOpen, required this.onAnswer});

  final WorklistItem item;
  final bool busy;
  final VoidCallback onOpen;
  final void Function(bool redirect) onAnswer;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final signal = item.patientSignal;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          decoration: signal == null ? null : BoxDecoration(border: Border(left: BorderSide(color: colors.accent, width: 3))),
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(item.patientRef, style: theme.textTheme.titleSmall?.merge(AppType.numeric).copyWith(letterSpacing: 0.4))),
                  StatusChip(s.priorityShort(item.priority), tone: StatusTone.accent),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text('${s.waitingFor(item.daysWaiting)} · ${s.stageLabel(item.stageCode)}', style: theme.textTheme.bodySmall?.merge(AppType.numeric)),
              OrgName(item.moName, maxLines: 1),
              if (item.riskFlags.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Wrap(spacing: AppSpacing.xs, runSpacing: AppSpacing.xs, children: [for (final f in item.riskFlags) StatusChip(s.flagShort(f), tone: _tone(f))]),
              ],
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Icon(_nextIcon(item.nextActionCode), size: 16, color: colors.accent),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(s.nextActionShort(item.nextActionCode, item.nextAction), style: theme.textTheme.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
              ),
              if (signal != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  [
                    signal.kind == RouteCodes.requestRedirect ? s.patientAsks(shortOrgName(signal.toMoName ?? signal.toMoCode ?? '')) : s.patientSignalText(signal.kind, null),
                    if (signal.comment != null && signal.comment!.isNotEmpty) '„${signal.comment}“',
                  ].join(' — '),
                  style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    if (signal.toMoCode != null) ...[
                      Expanded(child: FilledButton(onPressed: busy ? null : () => onAnswer(true), child: Text(s.redirectHere))),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(child: OutlinedButton(onPressed: busy ? null : () => onAnswer(false), child: Text(s.keepHere))),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static IconData _nextIcon(String code) => switch (code) {
        'redirect_faster' => Icons.alt_route,
        'review_before_call' => Icons.fact_check_outlined,
        'clarify_date' => Icons.event_outlined,
        'wait_for_call' => Icons.hourglass_empty,
        _ => Icons.arrow_forward,
      };

  static StatusTone _tone(String flag) => switch (flag) {
        'refusal_risk' => StatusTone.danger,
        'stuck_over_30' => StatusTone.warn,
        _ => StatusTone.accent,
      };
}
