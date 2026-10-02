import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/api_error.dart';
import '../widgets/app_card.dart';
import '../widgets/bell_button.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/doctor/worklist_logic.dart';
import '../widgets/doctor/worklist_row.dart';
import '../widgets/doctor/worklist_toolbar.dart';
import '../widgets/empty_state.dart';
import '../widgets/format.dart';
import '../widgets/load_state_view.dart';
import '../widgets/origin_tag.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_view.dart';

/// «Пациенты» врача — рабочий список (веб W-Worklist): подзаголовок «регион · Плановая госпитализация · данные на … ·
/// список синтетический», пометка о расчёте без модели, баннер устаревших данных; селектор флагов со счётчиками
/// (вместо KPI-плиток, Q-3), поиск по номеру и сортировка; строки с бейджем приоритета 0…10, чипом статуса, запросом
/// пациента и следующим шагом. Тап по строке — сразу маршрут пациента (Q-4), кнопок в строке нет (Q-16). В шапке —
/// колокольчик персонала; ассистент направления (`referral.assist`) — в панели над списком и в пустом состоянии.
/// Список грузится целиком, фильтр, поиск и сортировка — на телефоне; при возвращении на вкладку (с маршрута, из
/// входящих, из уведомлений) список перечитывается, чтобы строка показывала новый шаг после решения.
class WorklistScreen extends StatefulWidget {
  const WorklistScreen({super.key});

  /// Путь вкладки «Пациенты».
  static const path = '/doctor/patients';

  /// Ассистент направления для нового пациента (Q-5): без привязки к пациенту.
  static const assistantPath = '/doctor/referral';

  @override
  State<WorklistScreen> createState() => _WorklistScreenState();
}

class _WorklistScreenState extends State<WorklistScreen> {
  LoadState<WorklistResponse> _state = const Loading();
  Map<String, String> _regions = const {};
  Map<String, String> _profiles = const {};
  String _filter = worklistFilterAll;
  WorklistSort _sort = WorklistSort.initial;
  final _query = TextEditingController();
  GoRouter? _router;
  String? _lastPath;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
    _loadRefdata();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.maybeOf(context);
    if (router != _router) {
      _router?.routerDelegate.removeListener(_onLocation);
      _router = router;
      _lastPath = _currentPath();
      router?.routerDelegate.addListener(_onLocation);
    }
  }

  @override
  void dispose() {
    _router?.routerDelegate.removeListener(_onLocation);
    _query.dispose();
    super.dispose();
  }

  String? _currentPath() {
    final router = _router;
    return router == null || router.routerDelegate.currentConfiguration.isEmpty ? null : router.state.uri.path;
  }

  /// Возврат на список с другого экрана — перечитать: решение на маршруте меняет шаг и флаги строки.
  void _onLocation() {
    final path = _currentPath();
    final returned = path == WorklistScreen.path && _lastPath != null && _lastPath != path;
    _lastPath = path;
    if (returned && mounted) {
      _load();
    }
  }

  /// Первая загрузка — скелетон; повторная (возврат, pull-to-refresh) держит прежний список на экране, ошибка
  /// повторной загрузки — снекбаром поверх него.
  Future<void> _load() async {
    if (_loading) {
      return;
    }
    _loading = true;
    final api = context.read<Session>().api;
    if (_state is! Loaded<WorklistResponse>) {
      setState(() => _state = const Loading());
    }
    try {
      final page = await api.worklistPage();
      if (mounted) {
        setState(() => _state = Loaded(page));
      }
    } on Object catch (e) {
      if (mounted) {
        if (_state is Loaded<WorklistResponse>) {
          await showApiError(context, e);
        } else {
          setState(() => _state = Failed(e));
        }
      }
    } finally {
      _loading = false;
    }
  }

  /// Названия региона и профилей коек для подзаголовка и строк. Справочник необязателен: без него регион не
  /// показывается, а строка остаётся без профиля — сам список от этого не зависит, поэтому ошибка не выводится.
  Future<void> _loadRefdata() async {
    final api = context.read<Session>().api;
    try {
      final (regions, profiles) = await (api.regions(), api.profiles()).wait;
      if (mounted) {
        setState(() {
          _regions = {for (final r in regions) r.kato: r.name};
          _profiles = {for (final p in profiles) p.code: p.name};
        });
      }
    } on Object catch (e) {
      debugPrint('worklist refdata unavailable: $e');
    }
  }

  void _resetFilters() => setState(() {
        _filter = worklistFilterAll;
        _query.clear();
      });

  void _open(WorklistItem item) {
    FocusManager.instance.primaryFocus?.unfocus();
    context.go('${WorklistScreen.path}/${Uri.encodeComponent(item.patientRef)}', extra: item);
  }

  void _openAssistant() {
    FocusManager.instance.primaryFocus?.unfocus();
    context.push(WorklistScreen.assistantPath);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final session = context.watch<Session>();
    final assist = session.can(Perm.referralAssist);
    final page = switch (_state) { Loaded<WorklistResponse>(:final data) => data, _ => null };
    final stale = page != null && StaleDataBanner.isStale(page.asOf);
    final region = _regions[page?.regionKato ?? session.region];
    final subtitle = [
      ?region,
      s.worklistSubtitle,
      if (page != null && page.asOf.isNotEmpty && !stale) s.asOfLabel(dateShort(page.asOf)),
      s.worklistSyntheticShort,
    ].join(' · ');
    return PageScaffold(
      leading: const HomeMarkAnchor(),
      title: s.worklistPatients,
      actions: const [BellButton()],
      onRefresh: _load,
      children: [
        Text(subtitle, style: theme.textTheme.bodySmall),
        if (page != null && !page.modelBacked) Text(s.worklistNoteFallback, style: theme.textTheme.bodySmall?.copyWith(color: AppPalette.of(context).ink)),
        if (stale) StaleDataBanner(asOf: page.asOf),
        LoadStateView<WorklistResponse>(
          state: _state,
          onRetry: _load,
          skeleton: const CardSkeleton(height: 320),
          builder: (_, data) => _list(context, data, assist),
        ),
      ],
    );
  }

  Widget _list(BuildContext context, WorklistResponse page, bool assist) {
    final s = S.at(context);
    if (page.items.isEmpty) {
      return EmptyState(
        icon: Icons.person_add_alt_outlined,
        title: s.worklistEmpty,
        body: s.worklistEmptyText,
        action: assist ? FilledButton(onPressed: _openAssistant, child: Text(s.worklistCreateReferral)) : null,
      );
    }
    final visible = visibleWorklist(page.items, filter: _filter, query: _query.text, sort: _sort, profileName: (code) => _profiles[code] ?? code);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WorklistToolbar(
          counts: worklistCounts(page.items),
          filter: _filter,
          onFilter: (value) => setState(() => _filter = value),
          sort: _sort,
          onSort: (value) => setState(() => _sort = value),
          query: _query,
          onQuery: () => setState(() {}),
          onAssistant: assist ? _openAssistant : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(child: Text(s.worklistShown(visible.length, page.items.length), style: Theme.of(context).textTheme.labelSmall)),
            const SizedBox(width: AppSpacing.sm),
            Flexible(child: OriginTag(originModelOrRule(page.modelBacked), note: page.modelBacked ? s.worklistNote : s.worklistNoteFallback)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        if (visible.isEmpty)
          FilteredEmptyState(body: s.worklistEmptyFilter, onReset: _resetFilters)
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Column(
                children: [
                  for (final (i, item) in visible.indexed)
                    WorklistRow(item: item, profileName: _profiles[item.profileCode], last: i == visible.length - 1, onOpen: () => _open(item)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
