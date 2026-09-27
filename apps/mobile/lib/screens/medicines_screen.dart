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
import '../widgets/empty_state.dart';
import '../widgets/error_box.dart';
import '../widgets/format.dart';
import '../widgets/origin_tag.dart';
import '../widgets/picker_sheet.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// «Проверка рецепта» по доске M-Medicines: soft-селектор нозологии (её требует API), поле «МНН или название» с
/// подсказками из списка МНН нозологии, карточка МНН с чипом «Покрыт ОСМС», карточка «Сроки обеспечения» строками
/// (половина · 9 из 10 · за 14 дней · дефицит) и подпись модели. Проверка идёт при выборе МНН, без кнопки.
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
  final _query = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
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
      await _select(_mnnId!);
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
      _query.clear();
    });
    await _loadMnn();
  }

  Future<void> _select(String mnnId) async {
    final s = S.at(context);
    _focus.unfocus();
    setState(() {
      _mnnId = mnnId;
      _query.text = s.mnnName(mnnId);
    });
    await _check();
  }

  /// Подсказки: МНН нозологии, чей код или подпись содержит введённое; пустой ввод — первые восемь.
  List<Mnn> _suggestions(S s) {
    final q = _query.text.trim().toLowerCase();
    final matching = q.isEmpty ? _mnns : _mnns.where((m) => m.id.toLowerCase().contains(q) || s.mnnName(m.id).toLowerCase().contains(q)).toList();
    return matching.take(8).toList();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final state = _state;
    final nosology = _nosologies.where((n) => n.id == _nosologyId).firstOrNull;
    final mnn = _mnns.where((m) => m.id == _mnnId).firstOrNull;
    final showSuggestions = _focus.hasFocus && _mnns.isNotEmpty;
    return PageScaffold(
      title: s.medicinesTitle,
      children: [
        PickerRow(
          label: s.nosologyShort,
          value: _nosologyId == null ? null : '${s.nosologyShort} $_nosologyId',
          placeholder: s.choosePlaceholder,
          detail: nosology == null ? null : s.rxPerYear(thousands(nosology.issued12m)),
          onTap: _pickNosology,
          enabled: _nosologies.isNotEmpty,
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FieldLabel(s.mnnFieldLabel),
            TextField(
              controller: _query,
              focusNode: _focus,
              autocorrect: false,
              enabled: _mnns.isNotEmpty,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: s.mnnFieldHint, prefixIcon: const Icon(Icons.search)),
            ),
          ],
        ),
        if (showSuggestions) _Suggestions(items: _suggestions(s), onPick: _select),
        if (_refdataError != null) ErrorBox(error: _refdataError, onRetry: _load),
        if (state == null)
          EmptyState(icon: Icons.medication_outlined, title: s.chooseMnn, body: s.chooseMnnBody)
        else
          switch (state) {
            Loading<CheckResponse>() => const Column(children: [CardSkeleton(height: 120), SizedBox(height: AppSpacing.md), CardSkeleton(height: 280)]),
            Failed<CheckResponse>(:final error) => ErrorBox(error: error, onRetry: _check),
            Loaded<CheckResponse>(:final data) => _Result(data: data, mnn: mnn, nosologyId: _nosologyId),
          },
      ],
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.items, required this.onPick});

  final List<Mnn> items;
  final void Function(String mnnId) onPick;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    if (items.isEmpty) {
      return AppCard(padding: AppCard.plain, child: Text(s.pickerNothingFound, style: Theme.of(context).textTheme.bodySmall));
    }
    return AppCard(
      padding: AppCard.list,
      child: Column(
        children: [
          for (final (i, m) in items.indexed)
            ListRow(title: s.mnnName(m.id), subtitle: s.rxPerYear(thousands(m.issued12m)), last: i == items.length - 1, onTap: () => onPick(m.id)),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.data, required this.mnn, required this.nosologyId});

  final CheckResponse data;
  final Mnn? mnn;
  final String? nosologyId;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final tones = AppTones.of(context);
    final noFillData = data.fillDaysP50 == null && data.fillDaysP90 == null && data.pFilled14d == null;
    final model = data.model;
    final program = s.programLine(data.program, data.category, nosologyId);
    final rows = <(String, String?, Widget)>[
      (s.fillHalf, null, RowValue(s.daysValue(days(data.fillDaysP50Model ?? data.fillDaysP50)), size: 15)),
      (s.fillNine, null, RowValue(s.upToDays(days(data.fillDaysP90)), size: 15)),
      (s.fillWithin14, null, RowValue(pct(data.pFilled14d), size: 15)),
      (
        s.shortageSection,
        data.shortage.basis.isEmpty ? null : data.shortage.basis,
        RowValue(
          data.shortage.flag ? s.shortageSigns(data.shortage.score.toStringAsFixed(1)) : s.shortageNoSigns,
          size: 15,
          color: data.shortage.flag ? tones.danger.fg : tones.ok.fg,
        ),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(mnn == null ? s.mnnShort : s.mnnName(mnn!.id), style: theme.textTheme.titleLarge)),
                  const SizedBox(width: 10),
                  StatusChip(data.covered ? s.coveredChip : s.notCoveredChip, tone: data.covered ? StatusTone.ok : StatusTone.danger),
                ],
              ),
              if (program.isNotEmpty) ...[const SizedBox(height: AppSpacing.sm), Text(program, style: theme.textTheme.bodySmall?.merge(AppType.numeric))],
              if (!data.covered) ...[const SizedBox(height: AppSpacing.xs), Text(s.notCovered, style: theme.textTheme.bodySmall)],
              if (mnn != null) ...[const SizedBox(height: AppSpacing.xs), Text(s.rxPerYear(thousands(mnn!.issued12m)), style: theme.textTheme.bodySmall?.merge(AppType.numeric))],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppCard(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardLabel(s.fillTimeSection, trailing: OriginTag(data.fillDaysP50Model != null ? Origin.ml : Origin.formula)),
              if (noFillData)
                Padding(padding: const EdgeInsets.only(top: AppSpacing.md), child: Text(s.fillNoData, style: theme.textTheme.bodySmall))
              else
                for (final (i, row) in rows.indexed) ListRow(title: row.$1, subtitle: row.$2, trailing: row.$3, last: i == rows.length - 1),
              const SizedBox(height: AppSpacing.sm),
              Text(
                [
                  if (model != null) s.modelDataLine(model.name, model.version, model.trainedThrough),
                  if (data.basis.isNotEmpty) data.basis,
                  s.pharmacyShort,
                ].join(' · '),
                style: theme.textTheme.labelSmall?.copyWith(color: AppPalette.of(context).faint),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
