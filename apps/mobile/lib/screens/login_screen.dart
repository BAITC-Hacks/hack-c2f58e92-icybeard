import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../config/env.dart';
import '../l10n/strings.dart';
import '../router/guards.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/circle_button.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/error_box.dart';
import '../widgets/hero_number.dart';
import '../widgets/origin_tag.dart';
import '../widgets/stage_stepper.dart';
import '../widgets/status_chip.dart';

/// Вход по доске Main: круглая кнопка языка справа сверху, «Добро пожаловать в darumen», карусель белых карточек о
/// том, что даёт приложение (стадия направления, прогноз ожидания, сроки анализов), подпись под ней, кнопки внизу:
/// primary — eGov mobile (до доступа от НИТ ведёт на лист «Скоро», ничего не имитирует), secondary — вход по логину
/// нижним листом Keycloak. Гостевого режима нет: без входа открыт только этот экран.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.from});

  final String? from;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _slides = 3;
  static const _autoAdvance = Duration(seconds: 4);

  final _pages = PageController();
  int _page = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _restartTimer());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  /// Автопрокрутка карусели; после жеста пользователя отсчёт начинается заново. При отключённых анимациях не крутим.
  void _restartTimer() {
    _timer?.cancel();
    if (!mounted || (MediaQuery.maybeDisableAnimationsOf(context) ?? false)) {
      return;
    }
    _timer = Timer.periodic(_autoAdvance, (_) {
      if (!_pages.hasClients) {
        return;
      }
      _pages.animateToPage((_page + 1) % _slides, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    });
  }

  void _egov() {
    final s = S.at(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.egovSoonTitle, style: Theme.of(sheet).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(s.egovSoonBody, style: Theme.of(sheet).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: () {
                Navigator.of(sheet).pop();
                _passwordSheet();
              },
              child: Text(s.loginWithPassword),
            ),
          ],
        ),
      ),
    );
  }

  void _passwordSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PasswordSheet(from: widget.from),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final headlines = [s.loginSlideStage, s.loginSlideForecast, s.loginSlideChecklist];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.md),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [LanguageButton()]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, 0),
                child: Column(
                  children: [
                    const SizedBox(height: AppSpacing.xl),
                    Text(s.loginWelcome, style: theme.textTheme.bodySmall),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const DarumenMark(size: 42),
                        const SizedBox(width: 10),
                        Text('darumen', style: theme.textTheme.displaySmall),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final cardHeight = (constraints.maxHeight - 88).clamp(160.0, 300.0);
                          return Column(
                            children: [
                              SizedBox(
                                height: cardHeight,
                                child: NotificationListener<ScrollNotification>(
                                  onNotification: (n) {
                                    if (n is ScrollStartNotification && n.dragDetails != null) {
                                      _restartTimer();
                                    }
                                    return false;
                                  },
                                  child: PageView.builder(
                                    controller: _pages,
                                    itemCount: _slides,
                                    onPageChanged: (i) => setState(() => _page = i),
                                    itemBuilder: (_, i) => _SlideCard(index: i),
                                  ),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 250),
                                child: Text(
                                  headlines[_page],
                                  key: ValueKey(_page),
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.md),
                              _Dots(count: _slides, current: _page),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: Env.egovEnabled ? null : _egov,
                    icon: const Icon(Icons.qr_code_2, size: 20),
                    label: Text(s.loginWithEgov),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(onPressed: _passwordSheet, child: Text(s.loginWithPassword)),
                  const SizedBox(height: AppSpacing.md),
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

class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.current});

  final int count;
  final int current;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(horizontal: 3),
            width: i == current ? 16 : AppSizes.dot,
            height: AppSizes.dot,
            decoration: BoxDecoration(color: i == current ? colors.accent : colors.dotIdle, borderRadius: BorderRadius.circular(AppRadius.xs)),
          ),
      ],
    );
  }
}

/// Пример этапов для карточки «Стадия направления»: третий из пяти — текущий.
const _demoStages = [
  RouteStage(code: RouteCodes.referralIssued, order: 1, title: '', status: RouteCodes.done),
  RouteStage(code: RouteCodes.examination, order: 2, title: '', status: RouteCodes.done),
  RouteStage(code: RouteCodes.waitlisted, order: 3, title: '', status: RouteCodes.current),
  RouteStage(code: RouteCodes.dateAssigned, order: 4, title: '', status: RouteCodes.upcoming),
  RouteStage(code: RouteCodes.hospitalized, order: 5, title: '', status: RouteCodes.upcoming),
];

/// Карточка карусели — белая, как карточки приложения; на низких экранах содержимое уменьшается целиком.
class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: constraints.maxWidth,
            child: switch (index) {
              0 => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CardLabel(s.loginValueStage, trailing: StatusChip(s.loginCardWaitlisted, tone: StatusTone.ok)),
                    const SizedBox(height: 14),
                    const StageStepper(stages: _demoStages),
                    const SizedBox(height: 14),
                    Text('3 / 5 · ${s.loginCardWaitlisted.toLowerCase()}', style: theme.textTheme.bodySmall?.merge(AppType.numeric)),
                  ],
                ),
              1 => HeroNumber(
                  label: s.loginValueForecast,
                  origin: Origin.ml,
                  value: s.heroUntil('21').$1,
                  unit: s.heroUntil('21').$2,
                  caption: s.loginCardHalf,
                ),
              _ => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CardLabel(s.loginValueChecklist, trailing: const OriginTag(Origin.formula)),
                    const SizedBox(height: AppSpacing.xs),
                    for (final (i, (name, valid)) in const [('ОАК', false), ('ЭКГ', false), ('ВИЧ', true), ('ФЛГ', true)].indexed)
                      ListRow(
                        title: name,
                        last: i == 3,
                        trailing: StatusChip(valid ? s.loginCardValid : s.loginCardExpired, tone: valid ? StatusTone.ok : StatusTone.danger),
                      ),
                  ],
                ),
            },
          ),
        ),
      ),
    );
  }
}

/// Нижний лист с логином и паролем Keycloak: ошибка под полем, сетевые сбои — ErrorBox с повтором.
class _PasswordSheet extends StatefulWidget {
  const _PasswordSheet({this.from});

  final String? from;

  @override
  State<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends State<_PasswordSheet> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
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
        final target = afterLogin(session, widget.from);
        Navigator.of(context).pop();
        context.go(target);
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

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.loginWithPassword, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),
          FieldLabel(s.usernameLabel),
          TextField(
            controller: _username,
            autofocus: true,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(hintText: s.usernameLabel),
          ),
          const SizedBox(height: AppSpacing.md),
          FieldLabel(s.passwordLabel),
          TextField(
            controller: _password,
            obscureText: !_showPassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _busy ? null : _login(),
            decoration: InputDecoration(
              hintText: s.passwordLabel,
              errorText: _invalid ? s.loginFailed : null,
              suffixIcon: IconButton(
                icon: Icon(_showPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(onPressed: _busy ? null : _login, child: Text(_busy ? s.loggingInButton : s.loginButton)),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBox(error: _error, onRetry: _busy ? null : _login),
          ],
        ],
      ),
    );
  }
}
