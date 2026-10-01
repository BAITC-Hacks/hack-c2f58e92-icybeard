import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../state/staff_bell_notifier.dart';
import '../theme/tokens.dart';
import '../widgets/api_error.dart';
import '../widgets/circle_button.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_box.dart';
import '../widgets/external_link.dart';
import '../widgets/incoming/incoming_action_sheet.dart';
import '../widgets/incoming/incoming_card.dart';
import '../widgets/incoming/incoming_filter.dart';
import '../widgets/incoming/incoming_filter_bar.dart';
import '../widgets/incoming/incoming_links.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_view.dart';

/// «Входящие направления» принимающей больницы — корень вкладки «Входящие» (`/doctor/incoming`, всем с
/// `worklist.view`), как `IncomingReferralsView.vue` веба, но карточками в одну колонку (03 §6.3). Порядок работы:
/// пациент соглашается → больница подтверждает приём с датой (до 30 дней) или отказывает с причиной → в день
/// госпитализации отмечает приём или неявку (дату можно перенести) → выписывает с эпикризом.
///
/// - Список `GET /journal/referrals/incoming?includeConfirmed=true` в серверном порядке (тяжёлые первыми); отбор —
///   на телефоне: этап со счётчиками, «Только тяжёлые», поиск по рефу, отправителю и профилю.
/// - Кнопки — только из `item.allowed` (и при `referral.confirm`). Каждое действие — лист; перед «Госпитализирован»
///   и «Не пришёл» — подтверждение (Q-13). Новый ключ идемпотентности на каждое нажатие; пока запрос в полёте, все
///   кнопки выключены. Успех → список перечитан, колокольчик обновлён (счётчик вкладки), тост веба. 409 и 404 → сначала
///   перечитать список, затем текст сервера; 422 — под полем листа; сеть и 5xx — «Сервер недоступен».
/// - После подтверждения реф ведёт на маршрут пациента — там же «Снять с листа ожидания» (Q-18).
/// - Без своей больницы (администратор, Q-2): состояние «не привязана к больнице» и ссылка на веб, без запроса
///   списка (сервер ответил бы 422 «Нужна организация»).
/// - Колокольчик показал другое число ждущих подтверждения (опрос раз в минуту) — список перечитывается сам.
class IncomingReferralsScreen extends StatefulWidget {
  const IncomingReferralsScreen({super.key});

  @override
  State<IncomingReferralsScreen> createState() => _IncomingReferralsScreenState();
}

class _IncomingReferralsScreenState extends State<IncomingReferralsScreen> {
  LoadState<List<IncomingReferral>> _state = const Loading();

  /// Перечитывание поверх показанного списка не удалось: список остаётся, над ним — ошибка с «Повторить».
  Object? _refreshError;
  Map<String, String> _profiles = const {};
  IncomingFilter _filter = IncomingFilter.none;
  final _query = TextEditingController();
  bool _searching = false;

  /// `decisionId` направления, чьё действие в полёте.
  String? _acting;

  /// Открыт лист действия или подтверждения — второе нажатие не откроет второй.
  bool _sheetOpen = false;

  /// Идёт перечитывание после действия или жеста — изменение колокольчика не запускает ещё одно.
  bool _syncing = false;
  int _generation = 0;
  bool _started = false;
  String? _moCode;
  StaffBellNotifier? _bell;

  /// Последнее увиденное число ждущих подтверждения; null — колокольчик ещё не ответил.
  int? _seenPending;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bell = Provider.of<StaffBellNotifier?>(context, listen: false);
    if (!identical(bell, _bell)) {
      _bell?.removeListener(_onBell);
      _bell = bell?..addListener(_onBell);
      _seenPending = bell?.bell?.pendingIncomingCount;
    }
    final moCode = Provider.of<Session>(context).moCode;
    if (_started && moCode == _moCode) {
      return;
    }
    _started = true;
    _moCode = moCode;
    _state = const Loading();
    _refreshError = null;
    if (moCode != null) {
      unawaited(_load());
      if (_profiles.isEmpty) {
        unawaited(_loadProfiles());
      }
    }
  }

  @override
  void dispose() {
    _bell?.removeListener(_onBell);
    _query.dispose();
    super.dispose();
  }

  /// Колокольчик опросил сервер: изменилось число ждущих подтверждения — пришёл или ушёл перевод, перечитать список.
  void _onBell() {
    final count = _bell?.bell?.pendingIncomingCount;
    if (count == null) {
      return;
    }
    final previous = _seenPending;
    _seenPending = count;
    if (previous != null && previous != count && !_syncing && _acting == null && _state is Loaded<List<IncomingReferral>> && mounted) {
      unawaited(_load());
    }
  }

  /// Загрузка списка. Скелетон — только при первой загрузке и по «Повторить» ([skeleton]); после действий и жеста
  /// карточки остаются на экране. Ответ устаревшего запроса отбрасывается.
  Future<void> _load({bool skeleton = false}) async {
    final session = context.read<Session>();
    if (session.moCode == null) {
      return;
    }
    final generation = ++_generation;
    if (skeleton) {
      setState(() => _state = const Loading());
    }
    try {
      final items = await session.api.incomingReferrals();
      if (mounted && generation == _generation) {
        setState(() {
          _state = Loaded(items);
          _refreshError = null;
        });
      }
    } catch (e, stack) {
      _reportUnexpected(e, stack);
      if (mounted && generation == _generation) {
        setState(() {
          if (_state is Loaded<List<IncomingReferral>>) {
            _refreshError = e;
          } else {
            _state = Failed(e);
          }
        });
      }
    }
  }

  Future<void> _loadProfiles() async {
    try {
      final profiles = await context.read<Session>().api.profiles();
      if (mounted) {
        setState(() => _profiles = {for (final p in profiles) p.code: p.name});
      }
    } on Exception {
      // справочник необязателен: без него карточка показывает код профиля, поиск ищет по коду
    }
  }

  /// Перечитать список и колокольчик вместе (жест, после действия): счётчик вкладки идёт за списком.
  Future<void> _sync() async {
    _syncing = true;
    try {
      await Future.wait([_load(), if (_bell != null) _bell!.refresh()]);
    } finally {
      _syncing = false;
    }
  }

  /// Одно действие с направлением: новый ключ идемпотентности, кнопки выключены, успех → [_sync]. 409 и 404 →
  /// [_sync] до возврата ошибки (состояние на сервере уже другое). null — успех, иначе ошибка запроса.
  Future<Object?> _perform(IncomingReferral item, Future<String> Function(ApiClient api, String key) call) async {
    if (!mounted) {
      return null;
    }
    final api = context.read<Session>().api;
    final key = newIdempotencyKey();
    setState(() => _acting = item.decisionId);
    try {
      await call(api, key);
      await _sync();
      return null;
    } catch (e, stack) {
      _reportUnexpected(e, stack);
      final kind = apiErrorKind(e);
      if (kind == ApiErrorKind.conflict || kind == ApiErrorKind.notFound) {
        await _sync();
      }
      return e;
    } finally {
      if (mounted) {
        setState(() => _acting = null);
      }
    }
  }

  Future<void> _onAction(IncomingReferral item, String action) async {
    if (_acting != null || _sheetOpen) {
      return;
    }
    _sheetOpen = true;
    try {
      final mode = IncomingSheetMode.of(action);
      if (mode != null) {
        await _openSheet(item, mode);
      } else if (action == RouteCodes.actionAdmit || action == RouteCodes.actionNoShow) {
        await _mark(item, admit: action == RouteCodes.actionAdmit);
      }
    } finally {
      _sheetOpen = false;
    }
  }

  Future<void> _openSheet(IncomingReferral item, IncomingSheetMode mode) async {
    final s = S.at(context);
    final result = await showIncomingActionSheet(
      context,
      mode: mode,
      item: item,
      onSubmit: (plannedAt, text) => _perform(
        item,
        (api, key) => switch (mode) {
          IncomingSheetMode.confirm =>
            api.confirmReferral(item.decisionId, patientRef: item.patientRef, plannedAt: plannedAt, comment: text, idempotencyKey: key),
          IncomingSheetMode.reject => api.rejectReferral(item.decisionId, patientRef: item.patientRef, reason: text, idempotencyKey: key),
          IncomingSheetMode.reschedule =>
            api.rescheduleReferral(item.decisionId, patientRef: item.patientRef, plannedAt: plannedAt, reason: text, idempotencyKey: key),
          IncomingSheetMode.discharge => api.dischargeReferral(item.decisionId, patientRef: item.patientRef, summary: text, idempotencyKey: key),
        },
      ),
    );
    if (!mounted || result == null) {
      return;
    }
    final error = result.error;
    if (error == null) {
      _toast(mode.doneText(s));
    } else {
      await showApiError(context, error);
    }
  }

  /// «Госпитализирован» и «Не пришёл»: подтверждение (Q-13), затем запрос без полей.
  Future<void> _mark(IncomingReferral item, {required bool admit}) async {
    final s = S.at(context);
    final confirmed = await askIncomingMark(
      context,
      item: item,
      title: admit ? s.incomingAdmitAsk : s.incomingNoShowAsk,
      body: admit ? s.incomingAdmitAskBody : s.incomingNoShowAskBody,
      action: admit ? s.incomingAdmitAction : s.incomingNoShowAction,
      danger: !admit,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final error = await _perform(
      item,
      (api, key) => admit
          ? api.admitReferral(item.decisionId, patientRef: item.patientRef, idempotencyKey: key)
          : api.noShowReferral(item.decisionId, patientRef: item.patientRef, idempotencyKey: key),
    );
    if (!mounted) {
      return;
    }
    if (error == null) {
      _toast(admit ? s.incomingAdmittedDone : s.incomingNoShowDone);
    } else {
      await showApiError(context, error);
    }
  }

  void _toast(String text) => ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), duration: const Duration(seconds: 4)));

  void _setFilter(IncomingFilter filter) => setState(() => _filter = filter);

  void _resetFilter() {
    _query.clear();
    setState(() => _filter = IncomingFilter.none);
  }

  void _toggleSearch() {
    if (_searching) {
      _query.clear();
    }
    setState(() {
      _searching = !_searching;
      _filter = _filter.withQuery('');
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final session = context.watch<Session>();
    if (session.moCode == null) {
      return PageScaffold(title: s.incomingTitle, leading: const DarumenMark(size: 28), children: const [_NoHospitalState()]);
    }
    return PageScaffold(
      title: s.incomingTitle,
      leading: const DarumenMark(size: 28),
      actions: [CircleIconButton(icon: _searching ? Icons.close : Icons.search, label: s.pickerSearchHint, onTap: _toggleSearch)],
      onRefresh: _sync,
      children: switch (_state) {
        Loading() => const [CardSkeleton(height: 180), CardSkeleton(height: 180)],
        Failed(:final error) => [ErrorState(error: error, onRetry: () => _load(skeleton: true))],
        Loaded(:final data) => _content(s, session, data),
      },
    );
  }

  List<Widget> _content(S s, Session session, List<IncomingReferral> items) {
    final theme = Theme.of(context);
    final visible = applyIncomingFilter(items, _filter, _profiles);
    final canAct = session.can(Perm.referralConfirm);
    return [
      Text('${s.incomingSubtitle} · ${s.incomingTotal(items.length)}', style: theme.textTheme.bodySmall),
      if (_refreshError != null) ErrorBox(error: _refreshError, onRetry: _sync),
      if (items.isEmpty)
        EmptyState(icon: Icons.inbox_outlined, title: s.incomingEmpty, body: s.incomingEmptyBody)
      else ...[
        IncomingFilterBar(items: items, filter: _filter, onChanged: _setFilter),
        if (_searching)
          TextField(
            controller: _query,
            autofocus: true,
            autocorrect: false,
            onChanged: (value) => _setFilter(_filter.withQuery(value)),
            decoration: InputDecoration(hintText: s.incomingSearchHint, prefixIcon: const Icon(Icons.search)),
          ),
        if (_filter.isActive) Text(s.incomingShown(visible.length, items.length), style: theme.textTheme.labelSmall),
        if (visible.isEmpty)
          FilteredEmptyState(onReset: _resetFilter)
        else
          for (final item in visible)
            IncomingCard(
              key: ValueKey('incoming-card-${item.decisionId}'),
              item: item,
              profileName: _profiles[item.profileCode] ?? '',
              canAct: canAct,
              busy: _acting != null,
              acting: _acting == item.decisionId,
              onAction: (action) => _onAction(item, action),
              onOpenRoute: item.confirmed ? () => context.go(patientRoutePath(item.patientRef)) : null,
            ),
        Text(s.incomingNote, style: theme.textTheme.labelSmall),
      ],
    ];
  }
}

/// Учётная запись без больницы (администратор системы, Q-2): входящие есть только у конкретной больницы, выбрать её
/// можно в веб-кабинете — кнопка «Открыть веб» ведёт прямо на страницу входящих.
class _NoHospitalState extends StatelessWidget {
  const _NoHospitalState();

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return EmptyState(
      icon: Icons.domain_disabled_outlined,
      title: s.incomingNoOrgTitle,
      body: s.incomingNoOrgBody,
      action: OutlinedButton.icon(
        style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(0, AppSizes.compact))),
        onPressed: () => openExternal(context, incomingWebUri()),
        icon: const Icon(Icons.open_in_new, size: 18),
        label: Text(s.openWeb),
      ),
    );
  }
}

/// Ошибка, которая не `Exception` (тело неожиданной формы — ошибка контракта), — ещё и в отчёт Flutter, чтобы не
/// потерялась за общим «не удалось загрузить».
void _reportUnexpected(Object error, StackTrace stack) {
  if (error is! Exception) {
    FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stack, library: 'incoming referrals'));
  }
}
