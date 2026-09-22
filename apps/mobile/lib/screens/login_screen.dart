import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../config/env.dart';
import '../l10n/strings.dart';
import '../router/guards.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/error_box.dart';

/// Вход: основная кнопка — eGov mobile (до появления доступа от НИТ ведёт на экран «Скоро», ничего не имитирует),
/// вторичная — логин и пароль Keycloak, ссылка — гость. Никаких предзаполненных учёток и подсказок с паролем.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.from});

  final String? from;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _passwordForm = false;
  bool _busy = false;
  Object? _error;
  bool _invalid = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final session = context.read<Session>();
    setState(() {
      _busy = true;
      _error = null;
      _invalid = false;
    });
    try {
      await session.login(_username.text.trim(), _password.text);
      if (mounted) {
        context.go(afterLogin(session, widget.from));
      }
    } on ApiException catch (e) {
      final invalid = e.title == 'invalid_grant' || e.status == 401;
      setState(() {
        _invalid = invalid;
        _error = invalid ? null : e;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _egov() {
    final s = S.at(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.egovSoonTitle, style: Theme.of(sheet).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(s.egovSoonBody),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: () {
                Navigator.of(sheet).pop();
                setState(() => _passwordForm = true);
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
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xxl, AppSpacing.xl, AppSpacing.xxl),
          children: [
            Text('Darumen', style: theme.textTheme.displaySmall?.copyWith(color: colors.accent)),
            const SizedBox(height: AppSpacing.xs),
            Text(s.loginTagline, style: theme.textTheme.titleMedium?.copyWith(color: colors.muted)),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton.icon(
              onPressed: Env.egovEnabled ? null : _egov,
              icon: const Icon(Icons.qr_code_2),
              label: Text(s.loginWithEgov),
            ),
            const SizedBox(height: AppSpacing.md),
            if (!_passwordForm)
              OutlinedButton(onPressed: () => setState(() => _passwordForm = true), child: Text(s.loginWithPassword))
            else ...[
              TextField(
                controller: _username,
                autofocus: true,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: s.usernameLabel, errorText: _invalid ? s.loginFailed : null),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _login(),
                decoration: InputDecoration(
                  labelText: s.passwordLabel,
                  suffixIcon: IconButton(
                    icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: _busy ? null : _login, child: Text(_busy ? s.loggingInButton : s.loginButton)),
            ],
            if (_error != null) ...[const SizedBox(height: AppSpacing.md), ErrorBox(error: _error)],
            const SizedBox(height: AppSpacing.lg),
            Center(child: TextButton(onPressed: () => context.go('/home'), child: Text(s.continueAsGuest))),
            const SizedBox(height: AppSpacing.xxl),
            Text(s.loginPrivacyNote, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
