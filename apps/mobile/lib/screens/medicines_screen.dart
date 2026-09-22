import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../widgets/error_box.dart';
import '../widgets/format.dart';
import '../widgets/kpi_tile.dart';
import '../widgets/origin_tag.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// Проверка рецепта: покрыт ли МНН программой, сроки обеспечения (правила по витринам — «формула», p50 модели —
/// «ML‑модель»), признаки дефицита. Публичный экран; нозология запоминается между запусками.
class MedicinesScreen extends StatefulWidget {
  const MedicinesScreen({super.key});

  @override
  State<MedicinesScreen> createState() => _MedicinesScreenState();
}

class _MedicinesScreenState extends State<MedicinesScreen> {
  List<Nosology> _nosologies = const [];
  List<Mnn> _mnns = const [];
  String? _nosologyId;
  String? _mnnId;
  LoadState<CheckResponse>? _state;
  Object? _refdataError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<Session>();
    try {
      final nosologies = await session.api.nosologies();
      if (!mounted) {
        return;
      }
      final remembered = session.lastNosology;
      setState(() {
        _nosologies = nosologies;
        _nosologyId = nosologies.any((n) => n.id == remembered) ? remembered : nosologies.firstOrNull?.id;
        _refdataError = null;
      });
      await _loadMnn();
      await _check();
    } catch (e) {
      if (mounted) {
        setState(() => _refdataError = e);
      }
    }
  }

  Future<void> _loadMnn() async {
    final nosologyId = _nosologyId;
    if (nosologyId == null) {
      return;
    }
    final mnns = await context.read<Session>().api.mnn(nosologyId);
    if (mounted) {
      // сервер отдаёт каждый МНН один раз; на случай старого API дедуплицируем — DropdownButton падает на повторах
      final unique = <String, Mnn>{for (final m in mnns) m.id: m};
      setState(() {
        _mnns = unique.values.toList();
        _mnnId = _mnns.firstOrNull?.id;
      });
    }
  }

  Future<void> _check() async {
    final session = context.read<Session>();
    setState(() => _state = const Loading());
    try {
      final result = await session.api.checkMedicine(mnnId: _mnnId, nosologyId: _nosologyId, regionKato: session.region);
      if (_nosologyId != null) {
        await session.rememberNosology(_nosologyId!);
      }
      if (mounted) {
        setState(() => _state = Loaded(result));
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
    final state = _state;
    return PageScaffold(
      title: s.medicinesTitle,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _nosologies.any((n) => n.id == _nosologyId) ? _nosologyId : null,
          decoration: InputDecoration(labelText: s.nosologyLabel),
          isExpanded: true,
          items: [for (final n in _nosologies) DropdownMenuItem(value: n.id, child: Text(s.nosologyItem(n.id, n.issued12m), overflow: TextOverflow.ellipsis))],
          onChanged: (v) async {
            setState(() => _nosologyId = v);
            await _loadMnn();
          },
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _mnns.any((m) => m.id == _mnnId) ? _mnnId : null,
          decoration: InputDecoration(labelText: s.mnnLabel),
          isExpanded: true,
          items: [for (final m in _mnns) DropdownMenuItem(value: m.id, child: Text(s.mnnItem(m.id, m.issued12m), overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _mnnId = v),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(onPressed: state is Loading ? null : _check, icon: const Icon(Icons.check_circle_outline), label: Text(s.checkButton)),
        if (_refdataError != null) ...[const SizedBox(height: AppSpacing.md), ErrorBox(error: _refdataError, onRetry: _load)],
        if (state != null)
          switch (state) {
            Loading<CheckResponse>() => const Padding(padding: EdgeInsets.only(top: AppSpacing.lg), child: KpiRowSkeleton()),
            Failed<CheckResponse>(:final error) => Padding(padding: const EdgeInsets.only(top: AppSpacing.md), child: ErrorBox(error: error, onRetry: _check)),
            Loaded<CheckResponse>(:final data) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle(s.coverageSection, origin: Origin.formula),
                  StatusChip(
                    data.covered ? s.coveredBy(data.program) : s.notCovered,
                    tone: data.covered ? StatusTone.ok : StatusTone.warn,
                    icon: data.covered ? Icons.check : Icons.info_outline,
                  ),
                  SectionTitle(s.fillTimeSection, origin: Origin.formula),
                  KpiRow(
                    children: [
                      KpiTile(value: days(data.fillDaysP50), label: s.kpiMedianDays),
                      KpiTile(value: days(data.fillDaysP90), label: s.kpiP90Days),
                      KpiTile(value: pct(data.pFilled14d), label: s.kpiWithin14),
                    ],
                  ),
                  if (data.fillDaysP50Model != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(child: KpiTile(value: days(data.fillDaysP50Model), label: s.kpiMedianDays, origin: Origin.ml)),
                        const SizedBox(width: AppSpacing.sm),
                        const Expanded(flex: 2, child: SizedBox.shrink()),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  Text(data.basis, style: theme.textTheme.bodySmall),
                  SectionTitle(s.shortageSection, origin: Origin.formula),
                  StatusChip(
                    data.shortage.flag ? s.shortageFlag(data.shortage.score) : s.noShortage,
                    tone: data.shortage.flag ? StatusTone.danger : StatusTone.ok,
                    icon: data.shortage.flag ? Icons.warning_amber_outlined : Icons.check,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(data.shortage.basis, style: theme.textTheme.bodySmall),
                  if (data.model != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(s.modelTrained(data.model!.name, data.model!.version, data.model!.trainedThrough), style: theme.textTheme.labelSmall),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Text(s.pharmacyHint, style: theme.textTheme.labelSmall),
                ],
              ),
          },
      ],
    );
  }
}
