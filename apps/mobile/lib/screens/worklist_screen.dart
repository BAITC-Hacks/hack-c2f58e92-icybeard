import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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
import '../widgets/origin_tag.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// Рабочий список врача: синтетические пациенты на реальных очередях региона, приоритет по модели ожидания и риска
/// отказа («ML‑модель»; «формула», если сервис моделей был недоступен). Тап открывает маршрут пациента.
class WorklistScreen extends StatefulWidget {
  const WorklistScreen({super.key});

  @override
  State<WorklistScreen> createState() => _WorklistScreenState();
}

class _WorklistScreenState extends State<WorklistScreen> {
  LoadState<WorklistResponse> _state = const Loading();
  String? _flag;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const Loading());
    try {
      final page = await context.read<Session>().api.worklistPage(flag: _flag);
      if (mounted) {
        setState(() => _state = Loaded(page));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  void _setFlag(String? flag) {
    setState(() => _flag = flag);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final flags = {'stuck_over_30': s.flagOver30, 'refusal_risk': s.flagRefusalRisk, 'faster_alternative': s.flagFasterAlt};
    return PageScaffold(
      title: s.worklistTitle,
      onRefresh: _load,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            FilterChip(label: Text(s.flagAll), selected: _flag == null, onSelected: (_) => _setFlag(null)),
            for (final f in flags.entries) FilterChip(label: Text(f.value), selected: _flag == f.key, onSelected: (_) => _setFlag(f.key)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        LoadStateView<WorklistResponse>(
          state: _state,
          onRetry: _load,
          skeleton: const ListSkeleton(count: 5, itemHeight: 96),
          isEmpty: (page) => page.items.isEmpty,
          empty: EmptyState(icon: Icons.people_outline, title: s.emptyDecisions),
          builder: (_, page) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('${s.worklistCaption} ${s.asOfLabel(dateShort(page.asOf))}', style: theme.textTheme.labelSmall)),
                  const SizedBox(width: AppSpacing.sm),
                  OriginTag(page.modelBacked ? Origin.ml : Origin.formula),
                ],
              ),
              if (!page.modelBacked) ...[const SizedBox(height: AppSpacing.xs), Text(s.modelUnavailableNote, style: theme.textTheme.labelSmall)],
              const SizedBox(height: AppSpacing.sm),
              for (final item in page.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Card(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      onTap: () => context.go('/doctor/patients/${Uri.encodeComponent(item.patientRef)}', extra: item),
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(child: Text(item.patientRef, style: theme.textTheme.titleSmall?.merge(AppType.numeric))),
                                StatusChip(s.priorityShort(item.priority), tone: StatusTone.accent),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text('${s.waitingFor(item.daysWaiting)} · ${s.stageLabel(item.stageCode)}', style: theme.textTheme.bodySmall?.merge(AppType.numeric)),
                            Text(item.moName, style: theme.textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                            if (item.riskFlags.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Wrap(
                                spacing: AppSpacing.xs,
                                runSpacing: AppSpacing.xs,
                                children: [for (final f in item.riskFlags) StatusChip(flags[f] ?? f, tone: _tone(f))],
                              ),
                            ],
                            const SizedBox(height: AppSpacing.sm),
                            Text(s.nextActionText(item.nextActionCode, item.nextAction), style: theme.textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static StatusTone _tone(String flag) => switch (flag) {
        'refusal_risk' => StatusTone.danger,
        'stuck_over_30' => StatusTone.warn,
        _ => StatusTone.accent,
      };
}
