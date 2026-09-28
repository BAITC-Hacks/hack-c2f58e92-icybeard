import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/service_status.dart';
import '../config/env.dart';
import '../l10n/strings.dart';
import '../router/guards.dart';
import '../state/service_status_notifier.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/app_card.dart';
import '../widgets/circle_button.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/error_box.dart';
import '../widgets/external_link.dart';
import 'otp_screen.dart';

/// Вход по доске M-Auth-Login: круглая кнопка языка справа, знак и «darumen», «Вход» и «Кабинет врача» (если на
/// устройстве в прошлый раз входил врач, иначе «Кабинет»); в белой карточке — «Войти через eGov mobile»: доступность
/// берётся из `GET /public/service-status` (`egov.available`); пока сервис недоступен, кнопка вторичная с подписью
/// «Сервис eGov mobile сейчас недоступен», а лист прямо говорит, что адрес Smart Bridge не предоставлен и входить
/// нужно по логину — ничего не имитирует; «или по логину», поля «Рабочая почта или логин» и «Пароль» с
/// «Показать», «Запомнить на 30 дней», «Забыли пароль?» и «Войти»; ниже — «Нет аккаунта? Зарегистрировать
/// организацию» (веб `/signup` в браузере). Ошибки — у поля. Keycloak не отличает неверный пароль от отсутствующего
/// кода TOTP, поэтому после отказа предлагается «Войти с кодом из приложения»; если на устройстве для этого логина
/// уже вводили код, экран кода открывается сразу. Гостевого режима нет.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.from});

  final String? from;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _usernameFocus = FocusNode();
  bool _showPassword = false;
  bool _remember = true;
  bool _busy = false;
  bool _invalid = false;
  String? _usernameError;
  String? _passwordError;
  Object? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _usernameFocus.dispose();
    super.dispose();
  }

  bool _validate() {
    final s = S.at(context);
    setState(() {
      _usernameError = _username.text.trim().isEmpty ? s.enterLogin : null;
      _passwordError = _password.text.isEmpty ? s.enterPassword : null;
    });
    return _usernameError == null && _passwordError == null;
  }

  void _openOtp() {
    if (!_validate()) {
      return;
    }
    context.push('/login/otp', extra: OtpRequest(username: _username.text.trim(), password: _password.text, remember: _remember, from: widget.from));
  }

  Future<void> _login() async {
    if (_busy || !_validate()) {
      return;
    }
    final session = context.read<Session>();
    final username = _username.text.trim();
    if (session.needsOtp(username)) {
      _openOtp();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _invalid = false;
    });
    try {
      await session.login(username, _password.text, remember: _remember);
      if (mounted) {
        context.go(afterLogin(session, widget.from));
      }
    } on ApiException catch (e) {
      final invalid = e.title == 'invalid_grant' || e.status == 401;
      if (mounted) {
        setState(() {
          _invalid = invalid;
          _error = invalid ? null : e;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// Лист eGov: сервис недоступен — почему (адрес Smart Bridge не предоставлен) и «Войти по логину»; сервис
  /// доступен — честно, что в этой версии приложения вход через eGov ещё не реализован.
  void _egov(ServiceAvailability egov) {
    final s = S.at(context);
    final title = egov.isUp ? s.egovNotInAppTitle : s.egovUnavailableTitle;
    final body = egov.isUp ? s.egovNotInAppBody : s.egovUnavailableBody(egov.reason);
    // по высоте содержимого и с прокруткой: казахский текст на крупном шрифте не помещается в 9/16 экрана
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(sheet).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(body, style: Theme.of(sheet).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: () {
                Navigator.of(sheet).pop();
                _usernameFocus.requestFocus();
              },
              child: Text(s.loginWithPassword),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final lastShell = context.select<Session, ShellKind?>((x) => x.lastShell);
    final egov = ServiceStatusNotifier.watch(context).egov;
    final fieldStyle = theme.textTheme.bodyMedium?.copyWith(fontSize: 15);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, 0),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [LanguageButton()]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.xl),
                children: [
                  _Heading(subtitle: lastShell == ShellKind.doctor ? s.cabinetDoctor : s.cabinet),
                  const SizedBox(height: AppSpacing.lg),
                  AppCard(
                    padding: AppCard.plain,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _EgovButton(egov: egov, onPressed: () => _egov(egov)),
                          const SizedBox(height: AppSpacing.lg),
                          _OrDivider(text: s.orByLogin),
                          const SizedBox(height: AppSpacing.lg),
                          FieldLabel(s.loginEmailLabel),
                          TextField(
                            controller: _username,
                            focusNode: _usernameFocus,
                            autocorrect: false,
                            enableSuggestions: false,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username, AutofillHints.email],
                            style: fieldStyle,
                            onChanged: (_) {
                              if (_usernameError != null) {
                                setState(() => _usernameError = null);
                              }
                            },
                            decoration: InputDecoration(errorText: _usernameError),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          FieldLabel(s.passwordLabel),
                          TextField(
                            controller: _password,
                            obscureText: !_showPassword,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            style: fieldStyle,
                            onChanged: (_) {
                              if (_passwordError != null || _invalid) {
                                setState(() {
                                  _passwordError = null;
                                  _invalid = false;
                                });
                              }
                            },
                            onSubmitted: (_) => _login(),
                            decoration: InputDecoration(
                              errorText: _passwordError ?? (_invalid ? s.loginFailed : null),
                              errorMaxLines: 2,
                              suffixIcon: Padding(
                                padding: const EdgeInsets.only(right: AppSpacing.xs),
                                child: TextButton(
                                  onPressed: () => setState(() => _showPassword = !_showPassword),
                                  child: Text(_showPassword ? s.hidePassword : s.showPassword, style: theme.textTheme.titleSmall?.copyWith(fontSize: 13, color: colors.accentHover)),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          // в строку, как на доске; казахские подписи на крупном шрифте переносятся второй строкой
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: AppSpacing.sm,
                            children: [
                              _RememberBox(value: _remember, label: s.rememberMe, onChanged: (v) => setState(() => _remember = v)),
                              TextButton(onPressed: () => context.push('/login/forgot'), child: Text(s.forgotPassword, style: const TextStyle(fontSize: 14))),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          FilledButton(onPressed: _busy ? null : _login, child: Text(_busy ? s.loggingInButton : s.loginButton)),
                          if (_invalid) ...[
                            const SizedBox(height: AppSpacing.md),
                            Text(s.loginFailedOtpHint, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                            TextButton(onPressed: _busy ? null : _openOtp, child: Text(s.loginWithCode)),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: AppSpacing.md),
                            ErrorBox(error: _error, onRetry: _busy ? null : _login),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(s.noAccount, style: theme.textTheme.bodySmall),
                      TextButton(
                        onPressed: () => openExternal(context, Uri.parse('${Env.webBase}/signup')),
                        child: Text(s.registerOrganization, style: const TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(s.loginPrivacyNote, style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Войти через eGov mobile»: сервис доступен — primary; недоступен — вторичная кнопка (главным становится вход по
/// логину) и подпись «Сервис eGov mobile сейчас недоступен» под ней. Кнопка остаётся нажимаемой — лист объясняет почему.
class _EgovButton extends StatelessWidget {
  const _EgovButton({required this.egov, required this.onPressed});

  final ServiceAvailability egov;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final icon = const Icon(Icons.qr_code_2, size: 20);
    final label = Text(s.loginWithEgov);
    if (egov.isUp) {
      return FilledButton.icon(onPressed: onPressed, icon: icon, label: label);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(onPressed: onPressed, icon: icon, label: label),
        const SizedBox(height: 6),
        Text(s.egovUnavailableCaption, key: const ValueKey('egov-unavailable'), style: Theme.of(context).textTheme.labelSmall, textAlign: TextAlign.center),
      ],
    );
  }
}

/// Знак 28 и «darumen» 20/600, «Вход» 24/500, подпись кабинета 15 ink-2 — по центру.
class _Heading extends StatelessWidget {
  const _Heading({required this.subtitle});

  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.lg, 0, AppSpacing.sm),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const DarumenMark(size: 28),
              const SizedBox(width: 10),
              Text('darumen', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4)),
            ],
          ),
          const SizedBox(height: 6),
          Semantics(header: true, child: Text(s.loginTitle, style: theme.textTheme.headlineSmall)),
          const SizedBox(height: 6),
          Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(fontSize: 15)),
        ],
      ),
    );
  }
}

/// Разделитель «или по логину»: две линии hairline и подпись 12 ink-2 между ними.
class _OrDivider extends StatelessWidget {
  const _OrDivider({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          const Expanded(child: Divider()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(text, style: Theme.of(context).textTheme.labelSmall),
          ),
          const Expanded(child: Divider()),
        ],
      );
}

/// Флажок «Запомнить на 30 дней» с зоной нажатия 44 px по всей подписи.
class _RememberBox extends StatelessWidget {
  const _RememberBox({required this.value, required this.label, required this.onChanged});

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () => onChanged(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSizes.compact),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(value: value, onChanged: (v) => onChanged(v ?? false), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(child: Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppPalette.of(context).ink))),
              ],
            ),
          ),
        ),
      );
}
