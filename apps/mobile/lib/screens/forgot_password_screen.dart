import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../l10n/strings.dart';
import '../state/service_status_notifier.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/app_card.dart';
import '../widgets/error_box.dart';
import '../widgets/notice_card.dart';
import '../widgets/section.dart';

/// Восстановление пароля по доске M-Auth-Forgot: «Укажите рабочую почту — пришлём ссылку», поле почты, «ссылка
/// действует 60 минут», «Отправить ссылку» → `POST /api/v1/public/password-reset {email}` (202). После ответа —
/// карточка «Проверьте почту». Новый пароль задаётся по ссылке из письма на странице Keycloak (доска M-Auth-Reset
/// в вебе), отдельного экрана в приложении нет. Ошибки: формат почты — у поля, нет эндпоинта или сбой — плашка.
/// Почтовый сервер недоступен (`GET /public/service-status`) — сверху карточка «Письмо сейчас не придёт» с просьбой
/// обратиться к администратору организации; отправка остаётся доступной, но после ответа экран не обещает письмо.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _email = TextEditingController();
  bool _busy = false;
  String? _fieldError;
  Object? _failure;
  String? _sentTo;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final s = S.at(context);
    final email = _email.text.trim();
    if (!_emailPattern.hasMatch(email)) {
      setState(() => _fieldError = s.invalidEmail);
      return;
    }
    final api = context.read<Session>().api;
    setState(() {
      _busy = true;
      _fieldError = null;
      _failure = null;
    });
    try {
      await api.requestPasswordReset(email);
      if (mounted) {
        setState(() => _sentTo = email);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          switch (e.status) {
            case 400 || 422:
              _fieldError = e.field('email') ?? e.field('Email') ?? s.invalidEmail;
            case 429:
              _fieldError = s.tooManyRequests;
            case 404 || 405 || 501:
              _failure = ApiException(e.status, s.resetUnavailable); // эндпоинта ещё нет на этом стенде
            default:
              _failure = e;
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
    final sent = _sentTo != null;
    final mailDown = ServiceStatusNotifier.watch(context).email.isDown;
    return PageScaffold(
      title: s.forgotTitle,
      bottom: sent
          ? OutlinedButton(onPressed: () => context.go('/login'), child: Text(s.backToLogin))
          : FilledButton(onPressed: _busy ? null : _submit, child: Text(_busy ? s.sendingLink : s.sendLink)),
      children: [
        if (mailDown) NoticeCard(key: const ValueKey('reset-mail-down'), icon: Icons.mail_outline, title: s.resetMailDownTitle, body: s.resetMailDownBody),
        AppCard(
          padding: AppCard.plain,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.forgotBody, style: theme.textTheme.bodySmall?.copyWith(fontSize: 15)),
              const SizedBox(height: AppSpacing.lg),
              FieldLabel(s.workEmail),
              TextField(
                controller: _email,
                enabled: !sent,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.send,
                autofillHints: const [AutofillHints.email],
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(errorText: _fieldError, errorMaxLines: 2),
              ),
              const SizedBox(height: 6),
              Text(s.linkValidFor, style: theme.textTheme.labelSmall),
            ],
          ),
        ),
        if (sent) _SentCard(email: _sentTo!, mailDown: mailDown),
        if (_failure != null) ErrorBox(error: _failure, onRetry: _busy ? null : _submit),
        Text(s.loginPrivacyNote, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// «Проверьте почту»: конверт в accent-soft круге, заголовок 15/800, адрес и подсказка про «Спам». Пока почтовый сервер
/// недоступен — «Запрос принят», письмо на адрес не отправится, сменить пароль поможет администратор организации.
class _SentCard extends StatelessWidget {
  const _SentCard({required this.email, required this.mailDown});

  final String email;
  final bool mailDown;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Semantics(
      liveRegion: true,
      child: AppCard(
        padding: AppCard.plain,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: AppSizes.iconButton,
                  height: AppSizes.iconButton,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: colors.accentSoft),
                  child: Icon(Icons.mail_outline, size: 20, color: colors.accentHover),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(mailDown ? s.requestAcceptedTitle : s.checkMailTitle, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(mailDown ? s.mailNotSentBody(email) : s.checkMailBody(email), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(mailDown ? s.askAdminNote : s.checkMailNote, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}
