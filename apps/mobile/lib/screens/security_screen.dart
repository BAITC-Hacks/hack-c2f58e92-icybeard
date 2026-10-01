import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../config/env.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../widgets/account/account_api.dart';
import '../widgets/account/security_cards.dart';
import '../widgets/api_error.dart';
import '../widgets/external_link.dart';
import '../widgets/load_state_view.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';

/// Безопасность аккаунта по доске M-Account-Security (из профиля): почта · организация; карточка «Вход» — пароль
/// «изменён N дн. назад» (тап — смена пароля на странице Keycloak в браузере, `kc_action=UPDATE_PASSWORD`), SMS-код
/// «Сервис ещё не подключён», приложение-аутентификатор «настроено/не настроено» с «Настроить» или «Перенастроить»
/// (`kc_action=CONFIGURE_TOTP`), резервные коды; карточка «Устройства» — сеансы с «Завершить», внизу «Завершить все,
/// кроме этого»; карточка «Последние входы». Данные — `GET /me/security`; ошибка загрузки — состояние W-States с
/// «Повторить», 403 — «Нет доступа»; ошибка действия — `showApiError` (404 «Сессия не найдена» — текст сервера и
/// перечитанный список, сбой сети — «Сервер недоступен»).
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  LoadState<SecurityDetails> _state = const Loading();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const Loading());
    try {
      final details = await context.read<Session>().api.mySecurityDetails();
      if (mounted) {
        setState(() => _state = Loaded(details));
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  /// Действие с сеансами: пока оно в полёте, все кнопки заблокированы; успех — сообщение и перечитанный список,
  /// 404 (сеанса уже нет) — текст сервера после перечитывания.
  Future<void> _run(Future<void> Function() call, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await call();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (mounted) {
        await _load();
      }
    } on Exception catch (e) {
      if (mounted) {
        await showApiError(context, e, reload: _load);
        if (mounted && apiErrorKind(e) == ApiErrorKind.notFound) {
          await _load();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _endSession(DeviceSession device) {
    final api = context.read<Session>().api;
    _run(() => api.endSession(device.id), S.at(context).sessionEnded);
  }

  void _endOthers() {
    final api = context.read<Session>().api;
    _run(api.endOtherSessions, S.at(context).otherSessionsEnded);
  }

  void _keycloak(String action) => openExternal(context, Env.keycloakAction(action));

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final session = context.watch<Session>();
    final identity = [session.email ?? session.username, if (session.organizationName != null) '«${session.organizationName}»'].whereType<String>().join(' · ');
    final details = switch (_state) { Loaded<SecurityDetails>(:final data) => data, _ => null };
    final hasOthers = details?.info.sessions.any((d) => !d.current) ?? false;
    return PageScaffold(
      title: s.securityTitle,
      onRefresh: _load,
      bottom: hasOthers ? OutlinedButton(onPressed: _busy ? null : _endOthers, child: Text(s.endOtherSessions)) : null,
      children: [
        if (identity.isNotEmpty) Text(identity, style: theme.textTheme.bodySmall),
        if (_busy) const LinearProgressIndicator(),
        LoadStateView<SecurityDetails>(
          state: _state,
          onRetry: _load,
          skeleton: const Column(children: [CardSkeleton(height: 200), SizedBox(height: AppSpacing.md), CardSkeleton(height: 180)]),
          builder: (_, data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SignInCard(details: data, onChangePassword: () => _keycloak('UPDATE_PASSWORD'), onConfigureOtp: () => _keycloak('CONFIGURE_TOTP')),
              const SizedBox(height: AppSpacing.md),
              DevicesCard(sessions: data.info.sessions, busy: _busy, onEnd: _endSession),
              const SizedBox(height: AppSpacing.md),
              RecentLoginsCard(logins: data.recentLogins),
              const SizedBox(height: AppSpacing.md),
              Text('${data.info.otpConfigured ? s.otpOnNote : s.otpOffNote} ${s.securityBrowserNote}', style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ],
    );
  }
}
