import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/citizen_route_controller.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/api_error.dart';
import '../widgets/citizen_more/request_sheet.dart';
import '../widgets/citizen_more/wait_cards.dart';
import '../widgets/citizen_more/wait_logic.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_box.dart';
import '../widgets/picker_sheet.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/wait_bars.dart';

/// «Сколько ждут» (веб `citizen/WaitView.vue`): короткий заголовок и подпись веба; выбор региона и профиля койки,
/// «Показать и соседние регионы»; результат идёт за выбором, без кнопки. Карточка «В среднем по региону» (фраза,
/// ≈ p50, p90, доля за 30 дней, ориентир Минздрава с источником) и «Где быстрее в регионе» (полосы одного цвета,
/// сравнение со средним, «Как считается» с индексом и сезонностью NHS). Гражданин просит врача рассмотреть больницу
/// только когда маршрут разрешает `request_transfer` и выбраны регион и профиль своего маршрута (решения Q8, Q23);
/// просьба идёт через `CitizenRouteController.requestTransfer` — маршрут и колокольчик следуют за ней. Выбор региона
/// здесь не меняет регион сессии: тот задаёт профиль, а смена персоны маршрута с экрана справки сбивала бы просьбы.
class WaitScreen extends StatefulWidget {
  const WaitScreen({super.key, this.regionKato, this.profileCode});

  final String? regionKato;
  final String? profileCode;

  @override
  State<WaitScreen> createState() => _WaitScreenState();
}

class _WaitData {
  const _WaitData(this.prediction, this.alternatives, this.index);

  final PredictResponse prediction;
  final List<Alternative> alternatives;
  final List<RegionIndex> index;
}

class _WaitScreenState extends State<WaitScreen> {
  List<Region> _regions = const [];
  List<BedProfile> _profiles = const [];
  RouteBenchmark? _target;
  List<SeasonPoint> _seasons = const [];
  String? _region;
  String? _profile;
  bool _neighbours = false;
  LoadState<_WaitData>? _state;
  Object? _refdataError;
  String? _locale;
  int _runId = 0;

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    _region = widget.regionKato ?? session.region;
    _profile = widget.profileCode ?? session.lastProfile;
    _loadSeasonality();
    final route = session.isCitizen ? context.read<CitizenRouteController?>() : null;
    // маршрут и первый расчёт — после первого кадра: уведомления и setState во время initState запрещены
    unawaited(Future.microtask(() async {
      if (_profile != null) {
        unawaited(_run());
      }
      if (route != null) {
        await route.ensureLoaded();
        _adoptRouteProfile(route);
      }
    }));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // названия регионов и профилей приходят на языке запроса — смена языка перечитывает справочник (X3)
    final locale = S.at(context).locale;
    if (_locale != locale) {
      _locale = locale;
      unawaited(_loadRefdata());
    }
  }

  ApiClient get _api => context.read<Session>().api;

  /// Без выбранного профиля экран открывается профилем своего маршрута — там кнопка просьбы и работает.
  void _adoptRouteProfile(CitizenRouteController controller) {
    final route = controller.route;
    if (!mounted || route == null || _profile != null || route.organization.profileCode.isEmpty) {
      return;
    }
    setState(() {
      _profile = route.organization.profileCode;
      _region = route.regionKato.isEmpty ? _region : route.regionKato;
    });
    unawaited(_run());
  }

  Future<void> _loadRefdata() async {
    try {
      final results = await Future.wait<Object>([_api.regions(), _api.profiles(), _api.routeStandard()]);
      if (mounted) {
        setState(() {
          _regions = results[0] as List<Region>;
          _profiles = results[1] as List<BedProfile>;
          _target = (results[2] as RouteStandard).target;
          _refdataError = null;
        });
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _refdataError = e);
      }
    }
  }

  /// Сезонность — необязательная часть «Как считается»: без неё страница работает как раньше.
  Future<void> _loadSeasonality() async {
    try {
      final seasons = await _api.seasonality();
      if (mounted) {
        setState(() => _seasons = seasons);
      }
    } on Exception {
      // без витрины сезонности строки NHS просто нет
    }
  }

  /// Прогноз, больницы и индекс по выбору; ответ устаревшего выбора отбрасывается.
  Future<void> _run() async {
    final session = context.read<Session>();
    final region = _region;
    final profile = _profile;
    if (region == null || profile == null) {
      return;
    }
    final id = ++_runId;
    setState(() => _state = const Loading());
    try {
      final body = {'regionKato': region, 'profileCode': profile};
      final results = await Future.wait<Object>([
        _api.predict(body),
        _api.alternatives({...body, 'includeNeighbors': _neighbours}),
        _api.regionIndex(profileCode: profile),
      ]);
      await session.rememberProfile(profile);
      if (mounted && id == _runId) {
        setState(() => _state = Loaded(_WaitData(results[0] as PredictResponse, results[1] as List<Alternative>, results[2] as List<RegionIndex>)));
      }
    } on Exception catch (e) {
      if (mounted && id == _runId) {
        setState(() => _state = Failed(e));
      }
    }
  }

  Future<void> _pickRegion() async {
    final chosen = await PickerSheet.show<String>(
      context,
      title: S.at(context).regionLabel,
      items: [for (final r in _regions) PickerItem(r.kato, r.name)],
      selected: _region,
    );
    if (chosen != null && mounted) {
      setState(() => _region = chosen);
      await _run();
    }
  }

  Future<void> _pickProfile() async {
    final chosen = await PickerSheet.show<String>(
      context,
      title: S.at(context).profileLabel,
      items: [for (final p in _profiles) PickerItem(p.code, p.name)],
      selected: _profile,
    );
    if (chosen != null && mounted) {
      setState(() => _profile = chosen);
      await _run();
    }
  }

  Future<void> _toggleNeighbours(bool value) async {
    setState(() => _neighbours = value);
    await _run();
  }

  /// «Попросить рассмотреть»: лист с необязательным комментарием, затем одна просьба через контроллер маршрута
  /// (свой ключ на нажатие, повторное нажатие во время запроса заблокировано; 409 — маршрут уже перечитан).
  Future<void> _request(Alternative alternative) async {
    final controller = context.read<CitizenRouteController>();
    final comment = await showWaitRequestSheet(context, alternative);
    if (comment == null || !mounted) {
      return;
    }
    final sent = S.at(context).requestSent;
    final error = await controller.requestTransfer(alternative.moCode, comment: comment);
    if (!mounted) {
      return;
    }
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(sent)));
    } else {
      await showApiError(context, error);
    }
  }

  String? _regionName(String kato) => _regions.where((r) => r.kato == kato).map((r) => r.name).firstOrNull;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final controller = context.watch<CitizenRouteController?>();
    final state = _state;
    final profileName = _profiles.where((p) => p.code == _profile).map((p) => p.name).firstOrNull;
    return PageScaffold(
      title: s.waitTitle,
      gap: AppSpacing.sm,
      children: [
        Text(s.waitLead, style: theme.textTheme.bodySmall),
        PickerRow(label: s.regionLabel, value: _region == null ? null : _regionName(_region!) ?? _region, placeholder: s.choosePlaceholder, onTap: _pickRegion, enabled: _regions.isNotEmpty),
        PickerRow(label: s.profileShort, value: profileName, placeholder: s.choosePlaceholder, onTap: _pickProfile, enabled: _profiles.isNotEmpty),
        MergeSemantics(
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.waitNeighbours, style: theme.textTheme.row),
            value: _neighbours,
            onChanged: state is Loading<_WaitData> ? null : _toggleNeighbours,
          ),
        ),
        if (_refdataError != null) ErrorBox(error: _refdataError, onRetry: _loadRefdata),
        if (state == null)
          EmptyState(icon: Icons.tune, title: s.waitPickTitle, body: s.waitPickText)
        else
          switch (state) {
            Loading<_WaitData>() => const Column(children: [CardSkeleton(height: 220), SizedBox(height: AppSpacing.md), CardSkeleton(height: 240)]),
            Failed<_WaitData>(:final error) => _noData(error)
                ? EmptyState(
                    icon: Icons.search_off,
                    title: s.noDataForProfile,
                    body: s.waitChangeProfileHint,
                    action: OutlinedButton(onPressed: _pickProfile, child: Text(s.changeProfile)),
                  )
                : ErrorBox(error: error, onRetry: _run),
            Loaded<_WaitData>(:final data) => _result(data, controller),
          },
      ],
    );
  }

  Widget _result(_WaitData data, CitizenRouteController? controller) {
    final route = controller?.route;
    final busy = controller?.isActing ?? false;
    final index = data.index.where((i) => i.regionKato == _region).firstOrNull;
    Widget? actionFor(Alternative a) {
      if (requestedHere(route, region: _region, profile: _profile, moCode: a.moCode)) {
        return const WaitRequestedChip();
      }
      if (!canRequestHere(route, region: _region, profile: _profile, moCode: a.moCode)) {
        return null;
      }
      return _RequestButton(key: ValueKey('wait-request-${a.moCode}'), onPressed: busy ? null : () => _request(a), sending: controller?.acting == a.moCode);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        WaitAverageCard(prediction: data.prediction, target: _target),
        const SizedBox(height: AppSpacing.md),
        WaitFasterCard(
          empty: data.alternatives.isEmpty,
          bars: WaitBars(alternatives: data.alternatives, regionP50: data.prediction.p50Days, regionName: _regionName, actionFor: actionFor),
          index: index,
          indexTotal: data.index.length,
          regionName: _region == null ? null : _regionName(_region!),
          asOf: data.prediction.model.trainedThrough,
          seasonal: seasonalHint(S.at(context), _seasons, currentMonth: DateTime.now().month),
        ),
      ],
    );
  }

  /// 404 / 422 прогноза — по выбранному профилю в регионе нет данных: «Сменить профиль», а не ошибка сервера.
  static bool _noData(Object error) => error is ApiException && (error.status == 404 || error.status == 422);
}

/// «Попросить рассмотреть» — ссылка-кнопка 44 dp; [sending] — эта просьба в полёте (индикатор вместо стрелки).
class _RequestButton extends StatelessWidget {
  const _RequestButton({super.key, required this.onPressed, required this.sending});

  final VoidCallback? onPressed;
  final bool sending;

  @override
  Widget build(BuildContext context) => TextButton.icon(
        style: TextButton.styleFrom(minimumSize: const Size(0, AppSizes.compact), padding: EdgeInsets.zero),
        onPressed: onPressed,
        icon: sending ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_forward, size: 18),
        label: Text(S.at(context).routeRequestConsider),
      );
}
