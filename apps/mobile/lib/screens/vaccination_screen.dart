import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/app_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/hero_number.dart';
import '../widgets/inline_disclosure.dart';
import '../widgets/load_state_view.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// Оценки охвата WUENIC (ВОЗ/ЮНИСЕФ) по Казахстану, доска M-Vaccination (решение Q13 — экран мобилки, у веба его
/// нет): hero-карточка первой вакцины («86 %» + «БЦЖ, 2021», чип bench «ВОЗ/ЮНИСЕФ · 2021», динамика по годам,
/// подпись об ориентире и тихая раскрывашка «Источник» — внешний ориентир, а не метка происхождения), остальные
/// вакцины строками с динамикой и процентом справа (ниже 80 % — янтарным).
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

  /// «2019 · 81 % → 2020 · 86 % → 2021 · 86 %».
  String trend({bool withPercent = true}) =>
      years.map((y) => '${y.year} · ${y.coveragePct.toStringAsFixed(0)}${withPercent ? ' %' : ''}').join(' → ');
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

/// Охват ниже этого порога (%) выделяется янтарным.
const _lowCoverage = 80;

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
    } on Exception catch (e) {
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
    return PageScaffold(
      title: s.vaccinationTitle,
      onRefresh: _load,
      children: [
        LoadStateView<List<VaccinationEstimate>>(
          state: _state,
          onRetry: _load,
          skeleton: const Column(children: [CardSkeleton(height: 200), SizedBox(height: AppSpacing.md), CardSkeleton(height: 180)]),
          isEmpty: (items) => items.isEmpty,
          empty: EmptyState(icon: Icons.vaccines_outlined, title: s.noVaccineData),
          builder: (_, items) {
            final groups = groupVaccines(items, s.locale);
            final first = groups.first;
            final rest = groups.skip(1).toList();
            final source = items.first;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      HeroNumber(
                        label: s.coverageKz,
                        trailing: StatusChip(s.whoChip(first.latest.year), tone: StatusTone.bench),
                        value: '${first.latest.coveragePct.toStringAsFixed(0)} %',
                        unit: '${first.title}, ${first.latest.year}',
                        caption: first.trend(),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(s.vaccinationBenchNote, style: theme.textTheme.labelSmall?.copyWith(color: colors.muted)),
                      InlineDisclosure(
                        title: s.sourceLabel,
                        style: DisclosureStyle.quiet,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${s.sourceLabel}: ${source.source}', style: theme.textTheme.labelSmall),
                            if (source.note != null && source.note!.isNotEmpty) ...[
                              const SizedBox(height: AppSpacing.xs),
                              Text(source.note!, style: theme.textTheme.labelSmall),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (rest.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppCard(
                    padding: AppCard.list,
                    child: Column(
                      children: [
                        for (final (i, g) in rest.indexed)
                          ListRow(
                            title: g.title,
                            subtitle: g.trend(withPercent: false),
                            last: i == rest.length - 1,
                            trailing: RowValue(
                              '${g.latest.coveragePct.toStringAsFixed(0)} %',
                              strong: true,
                              color: g.latest.coveragePct < _lowCoverage ? colors.warn : colors.ink,
                            ),
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
