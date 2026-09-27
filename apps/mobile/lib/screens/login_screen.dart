import 'dart:async';

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
import '../theme/typography.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/error_box.dart';

/// Вход по образцу приветственных экранов (MyFitnessPal на Mobbin): язык справа сверху, «Добро пожаловать в darumen»,
/// карусель из трёх карточек о том, что даёт приложение (стадия направления, прогноз ожидания, сроки анализов),
/// заголовок и точки под ней, а кнопки прижаты к низу — под большой палец: единственная заливная — eGov mobile
/// (до доступа от НИТ ведёт на лист «Скоро», ничего не имитирует), «Войти по логину» открывает нижний лист
/// с логином и паролем Keycloak. Никаких предзаполненных учёток.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.from});

  final String? from;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _slides = 3;
  static const _autoAdvance = Duration(seconds: 4);

  final _pages = PageController(viewportFraction: 0.86);
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
      _pages.animateToPage(
        (_page + 1) % _slides,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _egov() {
    final s = S.at(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl,
          0,
          AppSpacing.xl,
          AppSpacing.xxl,
        ),
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
    final colors = AppPalette.of(context);
    final session = context.watch<Session>();
    final headlines = [
      s.loginSlideStage,
      s.loginSlideForecast,
      s.loginSlideChecklist,
    ];
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.sm,
                AppSpacing.xl,
                0,
              ),
              child: Align(
                alignment: Alignment.centerRight,
                child: _LanguageToggle(
                  locale: session.locale,
                  onChanged: session.setLocale,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              s.loginWelcome,
              style: theme.textTheme.bodyMedium?.copyWith(color: colors.muted),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const DarumenMark(size: 30),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  'darumen',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: DarumenBrand.navy,
                    letterSpacing: -0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final cardHeight = (constraints.maxHeight - 96).clamp(
                    180.0,
                    360.0,
                  );
                  return Column(
                    children: [
                      SizedBox(
                        height: cardHeight,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (n) {
                            if (n is ScrollStartNotification &&
                                n.dragDetails != null) {
                              _restartTimer();
                            }
                            return false;
                          },
                          child: PageView.builder(
                            controller: _pages,
                            itemCount: _slides,
                            onPageChanged: (i) => setState(() => _page = i),
                            itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                              ),
                              child: _SlideCard(index: i),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                        ),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: Text(
                            headlines[_page],
                            key: ValueKey(_page),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < _slides; i++)
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              width: i == _page ? 18 : 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: i == _page
                                    ? colors.accent
                                    : colors.faint,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.md,
                AppSpacing.xl,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    onPressed: Env.egovEnabled ? null : _egov,
                    icon: const Icon(Icons.qr_code_2),
                    label: Text(s.loginWithEgov),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: _passwordSheet,
                    child: Text(s.loginWithPassword),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    s.loginPrivacyNote,
                    style: theme.textTheme.labelSmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Карточка карусели: Navy-фон бренда, внутри мини-превью экрана приложения (без фотографий и стока).
class _SlideCard extends StatelessWidget {
  const _SlideCard({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return Container(
      decoration: BoxDecoration(
        color: DarumenBrand.navy,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      // На низких экранах содержимое уменьшается целиком, а не переполняет карточку.
      child: LayoutBuilder(
        builder: (context, constraints) => FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: constraints.maxWidth,
            child: switch (index) {
              0 => _StageCard(s: s),
              1 => _ForecastCard(s: s),
              _ => _ChecklistCard(s: s),
            },
          ),
        ),
      ),
    );
  }
}

const _mist = DarumenBrand.mist;
const _sky = DarumenBrand.sky;
final _mistMuted = _mist.withValues(alpha: 0.72);

Widget _cardLabel(BuildContext context, String text) => Text(
  text,
  style: Theme.of(
    context,
  ).textTheme.labelMedium?.copyWith(color: _mistMuted, letterSpacing: 0.4),
);

Widget _panel({required Widget child}) => Container(
  padding: const EdgeInsets.all(AppSpacing.lg),
  decoration: BoxDecoration(
    color: _mist.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(AppRadius.lg),
    border: Border.all(color: _mist.withValues(alpha: 0.12)),
  ),
  child: child,
);

class _StageCard extends StatelessWidget {
  const _StageCard({required this.s});

  final S s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _cardLabel(context, s.loginValueStage.toUpperCase()),
        const SizedBox(height: AppSpacing.lg),
        _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _sky.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  s.loginCardWaitlisted,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _sky,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  for (var i = 0; i < 5; i++) ...[
                    Container(
                      width: i == 2 ? 16 : 10,
                      height: i == 2 ? 16 : 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i < 2
                            ? _sky
                            : (i == 2
                                  ? DarumenBrand.navy
                                  : _mist.withValues(alpha: 0.18)),
                        border: i == 2
                            ? Border.all(color: _sky, width: 3)
                            : null,
                      ),
                    ),
                    if (i < 4)
                      Expanded(
                        child: Container(
                          height: 3,
                          color: i < 2 ? _sky : _mist.withValues(alpha: 0.18),
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                '3 / 5 · ${s.loginCardWaitlisted.toLowerCase()}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: _mistMuted)
                    .merge(AppType.numeric),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.s});

  final S s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _cardLabel(context, s.loginValueForecast.toUpperCase()),
        const SizedBox(height: AppSpacing.lg),
        Text(
          s.loginCardNineOfTen,
          style: theme.textTheme.headlineMedium
              ?.copyWith(color: _mist, fontWeight: FontWeight.w600, height: 1.1)
              .merge(AppType.numeric),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          s.loginCardHalf,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: _mistMuted)
              .merge(AppType.numeric),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final h in [0.35, 0.55, 0.45, 0.8, 1.0, 0.7, 0.5])
              Expanded(
                child: Container(
                  height: 56 * h,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: h == 1.0 ? _sky : _sky.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({required this.s});

  final S s;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = [('ОАК', false), ('ЭКГ', false), ('ВИЧ', true), ('ФЛГ', true)];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _cardLabel(context, s.loginValueChecklist.toUpperCase()),
        const SizedBox(height: AppSpacing.lg),
        _panel(
          child: Column(
            children: [
              for (final (name, valid) in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: _mist,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: (valid ? _sky : _mist).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          valid ? s.loginCardValid : s.loginCardExpired,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: valid ? _sky : _mistMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
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
      padding: EdgeInsets.fromLTRB(
        AppSpacing.xl,
        0,
        AppSpacing.xl,
        AppSpacing.xl + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            s.loginWithPassword,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.lg),
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
                icon: Icon(
                  _showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _busy ? null : _login,
            child: Text(_busy ? s.loggingInButton : s.loginButton),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            ErrorBox(error: _error, onRetry: _busy ? null : _login),
          ],
        ],
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
    segments: const [
      ButtonSegment(value: 'ru', label: Text('РУС')),
      ButtonSegment(value: 'kk', label: Text('ҚАЗ')),
    ],
    selected: {locale},
    showSelectedIcon: false,
    style: const ButtonStyle(visualDensity: VisualDensity.compact),
    onSelectionChanged: (v) => onChanged(v.first),
  );
}
