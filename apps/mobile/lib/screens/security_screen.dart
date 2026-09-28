import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../config/env.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/app_card.dart';
import '../widgets/external_link.dart';
import '../widgets/format.dart';
import '../widgets/load_state_view.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// Безопасность аккаунта по доске M-Account-Security (из профиля): почта · организация; карточка «Вход» — пароль
/// «изменён N дн. назад» (тап — смена пароля на странице Keycloak в браузере, `kc_action=UPDATE_PASSWORD`), SMS-код
/// «Сервис ещё не подключён», приложение-аутентификатор «настроено/не настроено» (тап — `kc_action=CONFIGURE_TOTP`);
/// карточка «Устройства» — сеансы с «Завершить», внизу «Завершить все, кроме этого». Данные — `GET /me/security`;
/// ошибка — состояние W-States с «Повторить», 403 — «Нет доступа».
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  LoadState<SecurityInfo> _state = const Loading();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = const Loading());
    try {
      final info = await context.read<Session>().api.mySecurity();
      if (mounted) {
        setState(() => _state = Loaded(info));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  Future<void> _run(Future<void> Function() call, String done) async {
    final s = S.at(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await call();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (mounted) {
        await _load();
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(s.serverUnavailable(e))));
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
    final info = switch (_state) { Loaded<SecurityInfo>(:final data) => data, _ => null };
    final hasOthers = info?.sessions.any((d) => !d.current) ?? false;
    return PageScaffold(
      title: s.securityTitle,
      neutralBack: true,
      onRefresh: _load,
      bottom: hasOthers ? OutlinedButton(onPressed: _busy ? null : _endOthers, child: Text(s.endOtherSessions)) : null,
      children: [
        if (identity.isNotEmpty) Text(identity, style: theme.textTheme.bodySmall),
        if (_busy) const LinearProgressIndicator(),
        LoadStateView<SecurityInfo>(
          state: _state,
          onRetry: _load,
          skeleton: const Column(children: [CardSkeleton(height: 200), SizedBox(height: AppSpacing.md), CardSkeleton(height: 180)]),
          builder: (_, data) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SignInCard(info: data, onChangePassword: () => _keycloak('UPDATE_PASSWORD'), onConfigureOtp: () => _keycloak('CONFIGURE_TOTP')),
              const SizedBox(height: AppSpacing.md),
              _DevicesCard(sessions: data.sessions, busy: _busy, onEnd: _endSession),
              const SizedBox(height: AppSpacing.md),
              Text('${data.otpConfigured ? s.otpOnNote : s.otpOffNote} ${s.securityBrowserNote}', style: theme.textTheme.labelSmall),
            ],
          ),
        ),
      ],
    );
  }
}

class _SignInCard extends StatelessWidget {
  const _SignInCard({required this.info, required this.onChangePassword, required this.onConfigureOtp});

  final SecurityInfo info;
  final VoidCallback onChangePassword;
  final VoidCallback onConfigureOtp;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final colors = AppPalette.of(context);
    final age = info.passwordAgeDays(DateTime.now());
    Icon icon(IconData data) => Icon(data, size: 20, color: colors.ink);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.securitySignIn),
          ListRow(
            leading: icon(Icons.lock_outline),
            title: s.passwordRow,
            subtitle: age == null ? s.passwordChangedUnknown : s.passwordChanged(age),
            trailing: Text(s.changePassword, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14, color: colors.accentHover)),
            onTap: onChangePassword,
          ),
          // SMS-шлюза нет: подпись «Сервис ещё не подключён», как у каналов уведомлений, а не чип «включено»
          ListRow(leading: icon(Icons.sms_outlined), title: s.methodSms, subtitle: s.smsNotConnected),
          ListRow(
            leading: icon(Icons.phone_iphone),
            title: s.authenticatorApp,
            subtitle: info.otpConfigured ? null : s.configure,
            trailing: StatusChip(info.otpConfigured ? s.configured : s.notConfigured, tone: info.otpConfigured ? StatusTone.ok : StatusTone.neutral),
            onTap: info.otpConfigured ? null : onConfigureOtp,
            last: true,
          ),
        ],
      ),
    );
  }
}

class _DevicesCard extends StatelessWidget {
  const _DevicesCard({required this.sessions, required this.busy, required this.onEnd});

  final List<DeviceSession> sessions;
  final bool busy;
  final ValueChanged<DeviceSession> onEnd;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final ordered = [...sessions]..sort((a, b) => (b.current ? 1 : 0) - (a.current ? 1 : 0));
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.devicesSection),
          if (ordered.every((d) => d.current))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(s.noOtherSessions, style: Theme.of(context).textTheme.bodySmall),
            ),
          for (final (i, d) in ordered.indexed)
            ListRow(
              title: [d.device ?? s.unknownDevice, ?d.browser].join(' · '),
              strong: true,
              subtitle: [?d.ip, if (d.lastAccess != null) dateTimeShort(d.lastAccess)].join(' · '),
              last: i == ordered.length - 1,
              trailing: d.current
                  ? StatusChip(s.thisDevice, tone: StatusTone.accent)
                  : OutlinedButton(style: AppButtons.danger(context, small: true), onPressed: busy ? null : () => onEnd(d), child: Text(s.endSession)),
            ),
        ],
      ),
    );
  }
}
