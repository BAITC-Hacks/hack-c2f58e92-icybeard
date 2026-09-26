import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import '../widgets/empty_state.dart';
import '../widgets/load_state_view.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// Оценки охвата WUENIC (ВОЗ/ЮНИСЕФ) по Казахстану: одно предложение и чип «внешний ориентир», группы по вакцине
/// («БЦЖ · 2025 — 86 %» крупно, тонкая полоса, предыдущие годы мелко), годы строками по тапу, источник один раз внизу.
class VaccinationScreen extends StatefulWidget {
  const VaccinationScreen({super.key});

  @override
  State<VaccinationScreen> createState() => _VaccinationScreenState();
}

/// Одна вакцина: подпись и оценки по годам, по возрастанию года.
class VaccineGroup {
  const VaccineGroup(this.title, this.years);

  final String title;
  final List<VaccinationEstimate> years;

  VaccinationEstimate get latest => years.last;
  List<VaccinationEstimate> get previous => years.sublist(0, years.length - 1);
}

/// Группировка по коду вакцины с сохранением порядка API; годы внутри — по возрастанию.
List<VaccineGroup> groupVaccines(List<VaccinationEstimate> items, String locale) {
  final buckets = <String, List<VaccinationEstimate>>{};
  for (final item in items) {
    buckets.putIfAbsent(item.vaccine, () => []).add(item);
  }
  return [
    for (final entry in buckets.entries)
      VaccineGroup(entry.value.first.titleFor(locale), [...entry.value]..sort((a, b) => a.year.compareTo(b.year))),
  ];
}

class _VaccinationScreenState extends State<VaccinationScreen> {
  LoadState<List<VaccinationEstimate>> _state = const Loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const Loading());
    try {
      final items = await context.read<Session>().api.vaccination();
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
      title: s.vaccinationTitle,
      onRefresh: _load,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: Text(s.vaccinationLead, style: theme.textTheme.bodySmall)),
            const SizedBox(width: AppSpacing.sm),
            StatusChip(s.externalBenchmark, tone: StatusTone.neutral),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        LoadStateView<List<VaccinationEstimate>>(
          state: _state,
          onRetry: _load,
          skeleton: const ListSkeleton(count: 5, itemHeight: 88),
          isEmpty: (items) => items.isEmpty,
          empty: EmptyState(icon: Icons.vaccines_outlined, title: s.noVaccineData),
          builder: (_, items) {
            final groups = groupVaccines(items, s.locale);
            final source = items.first;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final group in groups) Padding(padding: const EdgeInsets.only(bottom: AppSpacing.sm), child: _VaccineCard(group: group)),
                const SizedBox(height: AppSpacing.sm),
                Text('${s.sourceLabel}: ${source.source}', style: theme.textTheme.labelSmall),
                if (source.note != null && source.note!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(source.note!, style: theme.textTheme.labelSmall),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _VaccineCard extends StatefulWidget {
  const _VaccineCard({required this.group});

  final VaccineGroup group;

  @override
  State<_VaccineCard> createState() => _VaccineCardState();
}

class _VaccineCardState extends State<_VaccineCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final group = widget.group;
    final latest = group.latest;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : AppDurations.fast * 1.5;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => setState(() => _expanded = !_expanded),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(child: Text('${group.title} · ${latest.year}', style: theme.textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: AppSpacing.sm),
                  Text('${latest.coveragePct.toStringAsFixed(0)} %', style: theme.textTheme.headlineSmall?.merge(AppType.numeric)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: LinearProgressIndicator(value: (latest.coveragePct / 100).clamp(0, 1), minHeight: 4, backgroundColor: colors.hairline),
              ),
              if (group.previous.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  group.previous.map((y) => y.coveragePct.toStringAsFixed(0)).join(' → '),
                  style: theme.textTheme.labelSmall?.merge(AppType.numeric),
                ),
              ],
              AnimatedSize(
                duration: duration,
                alignment: Alignment.topCenter,
                child: _expanded
                    ? Column(
                        children: [
                          const Divider(height: AppSpacing.xl),
                          for (final y in group.years)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  Text('${y.year}', style: theme.textTheme.bodyMedium?.merge(AppType.numeric)),
                                  const Spacer(),
                                  Text('${y.coveragePct.toStringAsFixed(0)} %', style: theme.textTheme.bodyMedium?.merge(AppType.numeric)),
                                ],
                              ),
                            ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
