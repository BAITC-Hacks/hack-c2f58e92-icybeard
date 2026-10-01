import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../config/env.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../widgets/account/account_api.dart';
import '../widgets/account/consent_cards.dart';
import '../widgets/api_error.dart';
import '../widgets/external_link.dart';
import '../widgets/section.dart';

/// «Данные и согласия» аккаунта (веб `ConsentsView.vue`, F16): `/profile/consents` (гражданин) и
/// `/doctor/profile/consents` (врач), вложенный экран профиля без плавающей навигации. Три карточки:
/// - «Согласия» — переключатели `PUT /me/consents/{code}`, обязательное заблокировано; пока одно сохраняется,
///   остальные ждут; после ответа — список, который записал сервер;
/// - «Журнал доступа к моим данным» — `GET /me/access-log`;
/// - «Мои данные» — копия данных открывается страницей веб-кабинета (решение Q17: файл на телефоне не скачивается),
///   «Запросить удаление учётной записи» — после листа подтверждения, `POST /me/deletion-request`.
/// Ошибки действий — `showApiError`: 422 без поля на экране — текст сервера, сбой сети и 5xx — «Сервер недоступен».
class ConsentsScreen extends StatefulWidget {
  const ConsentsScreen({super.key});

  @override
  State<ConsentsScreen> createState() => _ConsentsScreenState();
}

class _ConsentsScreenState extends State<ConsentsScreen> {
  LoadState<List<AccountConsent>> _consents = const Loading();
  LoadState<List<AccessLogEntry>> _log = const Loading();
  String? _pending;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  ApiClient get _api => context.read<Session>().api;

  Future<void> _reload() => Future.wait([_loadConsents(), _loadLog()]);

  Future<void> _loadConsents() async {
    setState(() => _consents = const Loading());
    final next = await _guard(_api.myConsents);
    if (mounted) {
      setState(() => _consents = next);
    }
  }

  Future<void> _loadLog() async {
    setState(() => _log = const Loading());
    final next = await _guard(_api.myAccessLog);
    if (mounted) {
      setState(() => _log = next);
    }
  }

  static Future<LoadState<T>> _guard<T>(Future<T> Function() call) async {
    try {
      return Loaded(await call());
    } on Exception catch (e) {
      return Failed(e);
    }
  }

  /// Переключатель согласия: значение меняется только после ответа сервера (как в вебе), остальные заблокированы.
  Future<void> _setConsent(AccountConsent consent, bool granted) async {
    setState(() => _pending = consent.code);
    try {
      final stored = await _api.setConsent(consent.code, granted: granted);
      if (mounted) {
        setState(() => _consents = Loaded(stored));
      }
    } on Exception catch (e) {
      if (mounted) {
        await showApiError(context, e, reload: _loadConsents);
      }
    } finally {
      if (mounted) {
        setState(() => _pending = null);
      }
    }
  }

  Future<void> _requestDeletion() async {
    if (!await confirmDeletion(context) || !mounted) {
      return;
    }
    final key = newIdempotencyKey();
    final messenger = ScaffoldMessenger.of(context);
    final sent = S.at(context).deletionSent;
    setState(() => _deleting = true);
    try {
      await _api.requestDeletion(idempotencyKey: key);
      messenger.showSnackBar(SnackBar(content: Text(sent)));
    } on Exception catch (e) {
      if (mounted) {
        await showApiError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  void _export() => openExternal(context, Uri.parse('${Env.webBase}/account/consents'));

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final session = context.watch<Session>();
    final count = switch (_consents) { Loaded<List<AccountConsent>>(:final data) => data.length, _ => null };
    final lead = [session.displayName ?? session.username, if (count != null) s.consentsCount(count), s.consentsAuditNote].whereType<String>().join(' · ');
    return PageScaffold(
      title: s.consentsTitle,
      onRefresh: _reload,
      children: [
        Text(lead, style: Theme.of(context).textTheme.bodySmall),
        ConsentsCard(state: _consents, onRetry: _loadConsents, onChanged: _setConsent, pending: _pending),
        AccessLogCard(state: _log, onRetry: _loadLog),
        MyDataCard(onExport: _export, onDelete: _requestDeletion, deleting: _deleting),
      ],
    );
  }
}
