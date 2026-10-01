import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/api_error.dart';
import '../widgets/doctor/route_action.dart';
import '../widgets/doctor_route_view.dart';
import '../widgets/empty_state.dart';
import '../widgets/format.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_view.dart';

/// «Маршрут пациента» для врача (веб W-Patient, `/doctor/patients/:ref`). Кнопки решений — только из
/// `progress.allowed` (сервер считает машину состояний): «Оставить в текущей», «Перевести в выбранную» (с отметкой
/// тяжести), «Отменить перевод», «Снять с листа ожидания»; каждое нажатие — свежий Idempotency-Key, пока запрос идёт,
/// все кнопки решений выключены. Успех — снекбар и перечитывание маршрута; 409 — сначала перечитывание, затем текст
/// сервера; 422 — сообщение у поля причины; сбой связи и 5xx — «Сервер недоступен». Состояния загрузки: скелетон с
/// номером пациента из строки списка, 404 — «Маршрут с таким рефом не найден», 403 — «Нет доступа» с причиной.
/// Ссылки: «Записать приём» — скрайб этого пациента (`scribe.use`, врач — сторона маршрута), «Подобрать в
/// ассистенте» — новое направление с больницей и профилем маршрута (`referral.assist`, Q-5), «Открыть входящие» —
/// принимающей стороне.
class PatientRouteScreen extends StatefulWidget {
  const PatientRouteScreen({super.key, required this.patientRef, this.preview});

  final String patientRef;

  /// Строка рабочего списка, с которой открыт маршрут, — для шапки, пока маршрут грузится.
  final WorklistItem? preview;

  @override
  State<PatientRouteScreen> createState() => _PatientRouteScreenState();
}

class _PatientRouteScreenState extends State<PatientRouteScreen> {
  LoadState<PatientRoute> _state = const Loading();

  /// Код действия в полёте; не null — кнопки решений выключены.
  String? _acting;

  /// Номер последней загрузки: ответ более ранней не перезаписывает более свежий.
  int _generation = 0;
  Map<String, String> _regions = const {};
  bool _regionsRequested = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Первая загрузка — скелетон; повторная (после действия, 409, pull-to-refresh) держит маршрут на экране, а ошибка
  /// повторной загрузки показывается снекбаром. Никогда не бросает.
  Future<void> _load() async {
    final generation = ++_generation;
    final api = context.read<Session>().api;
    if (_state is Failed<PatientRoute>) {
      setState(() => _state = const Loading());
    }
    try {
      final route = await api.patientRoute(widget.patientRef);
      if (!mounted || generation != _generation) {
        return;
      }
      setState(() => _state = Loaded(route));
      _loadRegions(route);
    } on Object catch (e) {
      if (!mounted || generation != _generation) {
        return;
      }
      if (_state is Loaded<PatientRoute>) {
        await showApiError(context, e);
      } else {
        setState(() => _state = Failed(e));
      }
    }
  }

  /// Названия регионов — только для подписи «сосед: …» у больниц соседнего региона. Без справочника подпись покажет
  /// код региона: решение от этого не зависит, поэтому ошибка не выводится.
  Future<void> _loadRegions(PatientRoute route) async {
    if (_regionsRequested || !route.alternatives.any((a) => a.isNeighborRegion)) {
      return;
    }
    _regionsRequested = true;
    try {
      final regions = await context.read<Session>().api.regions();
      if (mounted) {
        setState(() => _regions = {for (final r in regions) r.kato: r.name});
      }
    } on Object catch (e) {
      debugPrint('patient route regions unavailable: $e');
    }
  }

  /// Выполнить решение врача: один свежий ключ на нажатие, кнопки выключены до ответа; успех — снекбар и
  /// перечитывание, ошибка — по общему рецепту (409 — перечитать, затем текст; 422 по причине — у поля).
  Future<DoctorRouteOutcome> _perform(DoctorRouteAction action) async {
    if (_acting != null) {
      return (ok: false, reasonError: null);
    }
    final s = S.at(context);
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final ref = widget.patientRef;
    final key = newIdempotencyKey();
    setState(() => _acting = action.kind);
    try {
      await switch (action.kind) {
        RouteCodes.actionRedirect => api.redirectRoute(ref, toMoCode: action.toMoCode!, reason: action.reason, severe: action.severe, idempotencyKey: key),
        RouteCodes.actionCancelTransfer => api.cancelTransfer(ref, reason: action.reason, idempotencyKey: key),
        RouteCodes.actionClose => api.closeRoute(ref, reason: action.reason, idempotencyKey: key),
        _ => api.keepRoute(ref, reason: action.reason, idempotencyKey: key),
      };
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(_doneText(s, action.kind))));
      await _load();
      return (ok: true, reasonError: null);
    } on Object catch (e) {
      if (!mounted) {
        return (ok: false, reasonError: null);
      }
      await showApiError(context, e, reload: _load, fields: const ['reason']);
      return (ok: false, reasonError: apiFieldError(e, 'reason'));
    } finally {
      if (mounted) {
        setState(() => _acting = null);
      }
    }
  }

  static String _doneText(S s, String kind) => switch (kind) {
        RouteCodes.actionRedirect => s.redirectDone,
        RouteCodes.actionCancelTransfer => s.patientRouteCancelDone,
        RouteCodes.actionClose => s.patientRouteCloseDone,
        _ => s.keepDone,
      };

  String get _encodedRef => Uri.encodeComponent(widget.patientRef);

  void _openScribe() => context.go('/doctor/patients/$_encodedRef/scribe');

  void _openIncoming() => context.go('/doctor/incoming');

  void _toWorklist() => context.go('/doctor/patients');

  /// Ассистент — только для нового направления (Q-5): больница и профиль маршрута подставлены, пациент не передаётся.
  void _openAssistant(PatientRoute route) => context.push(Uri(
        path: '/doctor/referral',
        queryParameters: {'moCode': route.organization.moCode, 'profileCode': route.organization.profileCode},
      ).toString());

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final session = context.watch<Session>();
    return PageScaffold(
      title: s.patientRouteTitle,
      onRefresh: _load,
      children: [
        switch (_state) {
          Loading<PatientRoute>() => _LoadingRoute(patientRef: widget.patientRef, preview: widget.preview),
          Failed<PatientRoute>(:final error) => _failure(context, error),
          Loaded<PatientRoute>(:final data) => DoctorRouteView(
              route: data,
              onAction: _perform,
              busy: _acting != null,
              acting: _acting,
              regionNames: _regions,
              onRecordVisit: session.can(Perm.scribeUse) && data.progress?.side != RouteCodes.sideNone ? _openScribe : null,
              onAssistant: session.can(Perm.referralAssist) ? () => _openAssistant(data) : null,
              onOpenIncoming: _openIncoming,
            ),
        },
      ],
    );
  }

  Widget _failure(BuildContext context, Object error) {
    final s = S.at(context);
    if (error is ApiException && error.isNotFound) {
      return EmptyState(
        icon: Icons.search_off,
        title: s.patientRouteNotFound,
        body: widget.patientRef,
        action: OutlinedButton(style: AppButtons.small(context), onPressed: _toWorklist, child: Text(s.patientRouteWorklistLink)),
      );
    }
    return ErrorState(error: error, onRetry: _load);
  }
}

/// Пока маршрут грузится: номер пациента, «ждёт N дн. · больница» из строки списка и два скелетона карточек.
class _LoadingRoute extends StatelessWidget {
  const _LoadingRoute({required this.patientRef, this.preview});

  final String patientRef;
  final WorklistItem? preview;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final row = preview;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(patientRef, style: theme.textTheme.headlineSmall?.merge(AppType.numeric)),
        if (row != null) Text('${s.waitingFor(row.daysWaiting)} · ${shortOrgName(row.moName)}', style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.md),
        const CardSkeleton(height: 220),
        const SizedBox(height: AppSpacing.md),
        const CardSkeleton(height: 160),
      ],
    );
  }
}
