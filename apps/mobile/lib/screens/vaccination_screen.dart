import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/empty_state.dart';
import '../widgets/load_state_view.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// Оценки охвата вакцинацией WUENIC (ВОЗ/ЮНИСЕФ) по Казахстану — внешний ориентир, публичный справочник.
class VaccinationScreen extends StatefulWidget {
  const VaccinationScreen({super.key});

  @override
  State<VaccinationScreen> createState() => _VaccinationScreenState();
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
          children: [
            Expanded(child: Text(s.vaccinationCaption, style: theme.textTheme.bodySmall)),
            const SizedBox(width: AppSpacing.sm),
            StatusChip(s.externalBenchmark, tone: StatusTone.neutral),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        LoadStateView<List<VaccinationEstimate>>(
          state: _state,
          onRetry: _load,
          skeleton: const ListSkeleton(),
          isEmpty: (items) => items.isEmpty,
          empty: EmptyState(icon: Icons.vaccines_outlined, title: s.noOrgsForProfile),
          builder: (_, items) => Card(
            child: Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    title: Text('${items[i].titleFor(s.locale)} · ${items[i].year}'),
                    subtitle: Text(
                      [items[i].source, if (items[i].note != null && items[i].note!.isNotEmpty) items[i].note!].join(' · '),
                      style: theme.textTheme.bodySmall,
                    ),
                    trailing: Text('${items[i].coveragePct.toStringAsFixed(0)} %', style: theme.textTheme.titleMedium?.merge(AppType.numeric)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
