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
import '../widgets/error_box.dart';
import '../widgets/format.dart';
import '../widgets/kpi_tile.dart';
import '../widgets/origin_tag.dart';
import '../widgets/picker_sheet.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// «Лекарства»: селекторы-строки с поиском (нозология, МНН; объём рецептов второй строкой), статус-блок покрытия
/// ОСМС, три плитки сроков с одной меткой на блок, строка дефицита с одним предложением, другие МНН при этой
/// нозологии. Проверка идёт при выборе МНН, без кнопки. Публичный экран; нозология запоминается.
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
      await _loadMnn(pickFirst: true);
    } catch (e) {
      if (mounted) {
        setState(() => _refdataError = e);
      }
    }
  }

  Future<void> _loadMnn({bool pickFirst = false}) async {
    final nosologyId = _nosologyId;
    if (nosologyId == null) {
      return;
    }
    final mnns = await context.read<Session>().api.mnn(nosologyId);
    if (!mounted) {
      return;
    }
    final unique = <String, Mnn>{for (final m in mnns) m.id: m};
    setState(() {
      _mnns = unique.values.toList();
      _mnnId = pickFirst ? _mnns.firstOrNull?.id : null;
      _state = null;
    });
    if (_mnnId != null) {
      await _check();
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

  Future<void> _pickNosology() async {
    final s = S.at(context);
    final chosen = await PickerSheet.show<String>(
      context,
      title: s.nosologyLabel,
      items: [for (final n in _nosologies) PickerItem(n.id, '${s.nosologyShort} ${n.id}', detail: s.rxPerYear(thousands(n.issued12m)))],
      selected: _nosologyId,
    );
    if (chosen == null || !mounted || chosen == _nosologyId) {
      return;
    }
    setState(() {
      _nosologyId = chosen;
      _mnnId = null;
      _mnns = const [];
      _state = null;
    });
    await _loadMnn();
  }

  Future<void> _pickMnn() async {
    final s = S.at(context);
    final chosen = await PickerSheet.show<String>(
      context,
      title: s.mnnLabel,
      items: [for (final m in _mnns) PickerItem(m.id, s.mnnName(m.id), detail: s.rxPerYear(thousands(m.issued12m)))],
      selected: _mnnId,
    );
    if (chosen == null || !mounted) {
      return;
    }
    await _select(chosen);
  }

  Future<void> _select(String mnnId) async {
    setState(() => _mnnId = mnnId);
    await _check();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final state = _state;
    final nosology = _nosologies.where((n) => n.id == _nosologyId).firstOrNull;
    final mnn = _mnns.where((m) => m.id == _mnnId).firstOrNull;
    return PageScaffold(
      title: s.medicinesTitle,
      children: [
        PickerRow(
          label: s.nosologyShort,
          value: _nosologyId,
          placeholder: s.choosePlaceholder,
          detail: nosology == null ? null : s.rxPerYear(thousands(nosology.issued12m)),
          onTap: _pickNosology,
          enabled: _nosologies.isNotEmpty,
        ),
        const SizedBox(height: AppSpacing.sm),
        PickerRow(
          label: s.mnnShort,
          value: _mnnId,
          placeholder: s.choosePlaceholder,
          detail: mnn == null ? null : s.rxPerYear(thousands(mnn.issued12m)),
          onTap: _pickMnn,
          enabled: _mnns.isNotEmpty,
        ),
        if (_refdataError != null) ...[const SizedBox(height: AppSpacing.md), ErrorBox(error: _refdataError, onRetry: _load)],
        const SizedBox(height: AppSpacing.md),
        if (state == null)
          EmptyState(icon: Icons.medication_outlined, title: s.chooseMnn, body: s.chooseMnnBody)
        else
          switch (state) {
            Loading<CheckResponse>() => const Column(
                children: [Skeleton(height: 72, radius: AppRadius.md), SizedBox(height: AppSpacing.lg), KpiRowSkeleton()],
              ),
            Failed<CheckResponse>(:final error) => ErrorBox(error: error, onRetry: _check),
            Loaded<CheckResponse>(:final data) => _Result(
                data: data,
                others: [for (final m in _mnns) if (m.id != _mnnId) m],
                onPickMnn: _select,
              ),
          },
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.data, required this.others, required this.onPickMnn});

  final CheckResponse data;
  final List<Mnn> others;
  final void Function(String mnnId) onPickMnn;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final tones = AppTones.of(context);
    final tone = data.covered ? tones.ok : tones.warn;
    final noFillData = data.fillDaysP50 == null && data.fillDaysP90 == null && data.pFilled14d == null;
    final model = data.model;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Row(
            children: [
              Icon(data.covered ? Icons.check_circle : Icons.info_outline, color: tone.fg, size: 28),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(data.covered ? s.coveredTitle : s.notCoveredTitle, style: theme.textTheme.titleSmall?.copyWith(color: tone.fg)),
                    Text(data.covered ? s.programCategory(data.program, data.category) : s.notCovered, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionTitle(s.fillTimeSection, origin: Origin.formula),
        if (noFillData)
          Text(s.fillNoData, style: theme.textTheme.bodySmall)
        else
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
              Expanded(child: Text(s.modelMedianLine(days(data.fillDaysP50Model)), style: theme.textTheme.bodySmall?.merge(AppType.numeric))),
              const SizedBox(width: AppSpacing.sm),
              const OriginTag(Origin.ml),
            ],
          ),
        ],
        if (data.basis.isNotEmpty) ...[const SizedBox(height: AppSpacing.xs), Text(data.basis, style: theme.textTheme.labelSmall)],
        SectionTitle(s.shortageSection, origin: Origin.formula),
        StatusChip(
          data.shortage.flag ? s.shortageYes(data.shortage.score.toStringAsFixed(1)) : s.shortageNone,
          tone: data.shortage.flag ? StatusTone.danger : StatusTone.ok,
          icon: data.shortage.flag ? Icons.warning_amber_outlined : Icons.check,
        ),
        if (data.shortage.basis.isNotEmpty) ...[const SizedBox(height: AppSpacing.xs), Text(data.shortage.basis, style: theme.textTheme.bodySmall)],
        if (others.isNotEmpty) ...[
          SectionTitle(s.otherMnn),
          Card(
            child: Column(
              children: [
                for (final (i, m) in others.take(8).indexed) ...[
                  if (i > 0) const Divider(),
                  ListTile(
                    dense: true,
                    title: Text(s.mnnName(m.id)),
                    trailing: Text(s.rxPerYear(thousands(m.issued12m)), style: theme.textTheme.bodySmall?.merge(AppType.numeric)),
                    onTap: () => onPickMnn(m.id),
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(
          [if (model != null) s.modelTrained(model.name, model.version, model.trainedThrough), s.pharmacyShort].join(' · '),
          style: theme.textTheme.labelSmall,
        ),
      ],
    );
  }
}
