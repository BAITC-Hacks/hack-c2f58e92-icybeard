import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/citizen_more/medicine_cards.dart';
import '../widgets/citizen_more/medicines_api.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_box.dart';
import '../widgets/format.dart';
import '../widgets/picker_sheet.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';

/// «Проверка рецепта» (веб `MedicinesView.vue`, доска M-Medicines): подпись веба под заголовком, селектор
/// нозологии (её требует API), поле «МНН или название» с подсказками из МНН нозологии; первый МНН проверяется сразу,
/// любой выбор — тоже, без кнопки. Результат — карточка МНН (покрытие, сроки, дефицит, «Как считается») и «Другие
/// МНН при этой нозологии» (тап — проверить этот МНН). Регион — регион сессии.
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
  LoadState<MedicineCheck>? _state;
  Object? _refdataError;
  int _checkId = 0;
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
    } on Exception catch (e) {
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

  /// Проверка выбранного МНН; ответ устаревшего выбора отбрасывается.
  Future<void> _check() async {
    final session = context.read<Session>();
    final id = ++_checkId;
    setState(() => _state = const Loading());
    try {
      final result = await session.api.checkMedicineDetails(mnnId: _mnnId, nosologyId: _nosologyId, regionKato: session.region);
      if (_nosologyId != null) {
        await session.rememberNosology(_nosologyId!);
      }
      if (mounted && id == _checkId) {
        setState(() => _state = Loaded(result));
      }
    } on Exception catch (e) {
      if (mounted && id == _checkId) {
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
    final showSuggestions = _focus.hasFocus && _mnns.isNotEmpty;
    return PageScaffold(
      title: s.medicinesTitle,
      children: [
        Text(s.medLead, style: Theme.of(context).textTheme.bodySmall),
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
          EmptyState(icon: Icons.medication_outlined, title: s.medPickTitle)
        else
          switch (state) {
            Loading<MedicineCheck>() => const Column(children: [CardSkeleton(height: 320), SizedBox(height: AppSpacing.md), CardSkeleton(height: 160)]),
            Failed<MedicineCheck>(:final error) => ErrorBox(error: error, onRetry: _check),
            Loaded<MedicineCheck>(:final data) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MedicineResultCard(result: data, title: _mnnId == null ? '${s.nosologyShort} ${_nosologyId ?? ''}' : s.mnnName(_mnnId!), nosologyId: _nosologyId),
                  const SizedBox(height: AppSpacing.md),
                  OtherMnnCard(items: data.alternatives, onPick: _select),
                ],
              ),
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
