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

/// Вход: язык выбирают до входа (РУС / ҚАЗ справа сверху), знак и слоган, три строки ценности, единственная
/// заливная кнопка — eGov mobile (до доступа от НИТ ведёт на лист «Скоро», ничего не имитирует), контурная —
/// логин и пароль Keycloak с ошибкой под полем, гость текстом. Никаких предзаполненных учёток.
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
    final session = context.watch<Session>();
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.xxl),
          children: [
            Align(alignment: Alignment.centerRight, child: _LanguageToggle(locale: session.locale, onChanged: session.setLocale)),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: Icon(Icons.route_outlined, color: theme.colorScheme.onPrimary),
                ),
                const SizedBox(width: AppSpacing.md),
                Text('Darumen', style: theme.textTheme.headlineSmall?.copyWith(color: colors.accent)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(s.loginTagline, style: theme.textTheme.titleMedium?.copyWith(color: colors.muted)),
            const SizedBox(height: AppSpacing.xl),
            _ValueRow(icon: Icons.flag_outlined, label: s.loginValueStage),
            const SizedBox(height: AppSpacing.sm),
            _ValueRow(icon: Icons.science_outlined, label: s.loginValueChecklist),
            const SizedBox(height: AppSpacing.sm),
            _ValueRow(icon: Icons.schedule_outlined, label: s.loginValueForecast),
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
                decoration: InputDecoration(labelText: s.usernameLabel),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _password,
                obscureText: !_showPassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _busy ? null : _login(),
                decoration: InputDecoration(
                  labelText: s.passwordLabel,
                  errorText: _invalid ? s.loginFailed : null,
                  suffixIcon: IconButton(
                    icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                    onPressed: () => setState(() => _showPassword = !_showPassword),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: _busy ? null : _login, child: Text(_busy ? s.loggingInButton : s.loginButton)),
            ],
            if (_error != null) ...[const SizedBox(height: AppSpacing.md), ErrorBox(error: _error, onRetry: _busy ? null : _login)],
            const SizedBox(height: AppSpacing.lg),
            Center(child: TextButton(onPressed: () => context.go('/home'), child: Text(s.continueAsGuest))),
            const SizedBox(height: AppSpacing.xl),
            Text(s.loginPrivacyNote, style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _LanguageToggle extends StatelessWidget {
  const _LanguageToggle({required this.locale, required this.onChanged});

  final String locale;
  final void Function(String locale) onChanged;

  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
        segments: const [ButtonSegment(value: 'ru', label: Text('РУС')), ButtonSegment(value: 'kk', label: Text('ҚАЗ'))],
        selected: {locale},
        showSelectedIcon: false,
        style: const ButtonStyle(visualDensity: VisualDensity.compact, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
        onSelectionChanged: (v) => onChanged(v.first),
      );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(color: colors.accentSoft, borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: Icon(icon, size: 20, color: colors.accent),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyMedium)),
      ],
    );
  }
}
