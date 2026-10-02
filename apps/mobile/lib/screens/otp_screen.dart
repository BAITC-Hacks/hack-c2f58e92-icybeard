import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../l10n/strings.dart';
import '../router/guards.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/app_card.dart';
import '../widgets/error_box.dart';
import '../widgets/otp_field.dart';
import '../widgets/section.dart';
import '../widgets/status_chip.dart';

/// Логин и пароль, с которыми экран кода повторяет вход: живут только в памяти маршрута, не сохраняются.
class OtpRequest {
  const OtpRequest({required this.username, required this.password, required this.remember, this.from});

  final String username;
  final String password;
  final bool remember;
  final String? from;
}

/// Второй фактор по доске M-Auth-OTP: шесть ячеек с автопереходом и вставкой, «Код обновляется каждые 30 секунд»
/// (TOTP не отправляется повторно — таймера нет), карточка «Другой способ» — код из приложения (текущий), SMS —
/// «Сервис ещё не подключён», резервные коды — «после интеграции»; внизу «Подтвердить». Вход повторяется password grant с параметром `totp`;
/// Keycloak на неверный код и неверный пароль отвечает одинаково, поэтому ошибка у поля подсказывает оба варианта.
/// «Не спрашивать 30 дней» с доски не переносится: direct grant Keycloak не умеет доверенные устройства.
class OtpScreen extends StatefulWidget {
  const OtpScreen({super.key, required this.request});

  final OtpRequest request;

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _fieldError;
  Object? _failure;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = S.at(context);
    if (_busy) {
      return;
    }
    if (_code.text.length < 6) {
      setState(() => _fieldError = s.otpIncomplete);
      return;
    }
    final session = context.read<Session>();
    final r = widget.request;
    setState(() {
      _busy = true;
      _fieldError = null;
      _failure = null;
    });
    try {
      await session.login(r.username, r.password, otp: _code.text, remember: r.remember);
      if (mounted) {
        context.go(afterLogin(session, r.from));
      }
    } on ApiException catch (e) {
      if (mounted) {
        final invalid = e.title == 'invalid_grant' || e.status == 401;
        setState(() {
          _fieldError = invalid ? s.otpInvalid : null;
          _failure = invalid ? null : e;
          if (invalid) {
            _code.clear();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _failure = e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return PageScaffold(
      title: s.otpTitle,
      bottom: FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? s.otpChecking : s.otpConfirm)),
      children: [
        AppCard(
          padding: AppCard.plain,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.otpBody, style: theme.textTheme.bodyLarge?.copyWith(color: colors.muted)),
              const SizedBox(height: AppSpacing.lg),
              OtpField(
                controller: _code,
                label: s.otpFieldLabel,
                hasError: _fieldError != null,
                enabled: !_busy,
                onCompleted: (_) => _submit(),
              ),
              if (_fieldError != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(_fieldError!, style: theme.textTheme.labelSmall?.copyWith(color: colors.danger), key: const ValueKey('otp-error')),
              ],
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: colors.muted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s.otpRefreshHint, style: theme.textTheme.labelSmall)),
                ],
              ),
            ],
          ),
        ),
        AppCard(
          padding: AppCard.plain,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardLabel(s.otherMethod),
              const SizedBox(height: AppSpacing.sm),
              _MethodRow(icon: Icons.phone_iphone, title: s.methodApp, chip: StatusChip(s.currentMethod, tone: StatusTone.accent)),
              const SizedBox(height: AppSpacing.sm),
              _MethodRow(icon: Icons.sms_outlined, title: s.methodSms, chip: Text(s.smsNotConnected, style: theme.textTheme.labelSmall, textAlign: TextAlign.end), disabled: true),
              const SizedBox(height: AppSpacing.sm),
              _MethodRow(icon: Icons.password_outlined, title: s.methodBackup, chip: Text(s.afterIntegration, style: theme.textTheme.labelSmall, textAlign: TextAlign.end), disabled: true),
            ],
          ),
        ),
        if (_failure != null) ErrorBox(error: _failure, onRetry: _busy ? null : _submit),
        Text(s.loginPrivacyNote, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// Способ подтверждения: строка на surface-hover radius 14 min-height 56 — иконка, название 13.5/700, чип справа.
/// SMS и резервные коды недоступны до интеграции и не нажимаются.
class _MethodRow extends StatelessWidget {
  const _MethodRow({required this.icon, required this.title, required this.chip, this.disabled = false});

  final IconData icon;
  final String title;
  final Widget chip;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final color = disabled ? colors.muted : colors.ink;
    return Semantics(
      enabled: !disabled,
      child: Container(
        constraints: const BoxConstraints(minHeight: AppSizes.row),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: colors.surfaceHover, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Row(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 3, child: Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color))),
            const SizedBox(width: AppSpacing.sm),
            Flexible(flex: 2, child: Align(alignment: Alignment.centerRight, child: chip)),
          ],
        ),
      ),
    );
  }
}
