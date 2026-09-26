import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/error_box.dart';
import '../widgets/format.dart';
import '../widgets/org_name.dart';
import '../widgets/origin_tag.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/stage_stepper.dart';
import '../widgets/status_chip.dart';

/// Главная гражданина по образцу NHS App: карточка «Моя госпитализация» (профиль · короткое имя организации, чип
/// стадии и мини-степпер, главная строка «9 из 10 — до N дн.», строка «что сейчас» с «Да, жду» прямо в карточке),
/// над ней — ответ врача, если он есть; ниже три равные плитки. Никаких новостей и баннеров.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LoadState<PatientRoute> _state = const Loading();
  bool? _loadedFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authenticated = context.watch<Session>().isAuthenticated;
    if (authenticated != _loadedFor) {
      _loadedFor = authenticated;
      _load();
    }
  }

  Future<void> _load() async {
    final session = context.read<Session>();
    if (!session.isAuthenticated) {
      return;
    }
    setState(() => _state = const Loading());
    try {
      final route = await session.api.myRoute(regionKato: session.regionFromAccount ? null : session.region);
      if (mounted) {
        setState(() => _state = Loaded(route));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  /// «Да, жду» прямо в карточке: один Idempotency-Key на нажатие, после ответа маршрут перечитывается.
  Future<void> _stillWaiting() async {
    final session = context.read<Session>();
    final s = S.at(context);
    try {
      await session.api.sendRouteSignal(
        RouteCodes.stillWaiting,
        idempotencyKey: newIdempotencyKey(),
        regionKato: session.regionFromAccount ? null : session.region,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.signalSent)));
        await _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s.serverUnavailable(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final session = context.watch<Session>();
    final theme = Theme.of(context);
    final answer = switch (_state) {
      Loaded<PatientRoute>(data: final route) when route.latestDecision != null && route.latestDecision!.decisionId != session.seenDecisionId =>
        route.latestDecision,
      _ => null,
    };
    return PageScaffold(
      title: s.navHome,
      leading: const HomeMarkAnchor(),
      onRefresh: session.isAuthenticated ? _load : null,
      children: [
        if (!session.isAuthenticated) ...[
          _GuestCard(s: s),
          const SizedBox(height: AppSpacing.md),
          _DailyCards(regionKato: session.region),
        ] else ...[
          if (answer != null) ...[_AnswerCard(decision: answer), const SizedBox(height: AppSpacing.md)],
          _RouteCard(state: _state, onRetry: _load, onStillWaiting: _stillWaiting),
        ],
        const SizedBox(height: AppSpacing.lg),
        // IntrinsicHeight: плитки одной высоты внутри ListView (stretch без него даёт бесконечную высоту)
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _Tile(icon: Icons.schedule_outlined, label: s.homeTileWait, onTap: () => context.go('/home/wait'))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _Tile(icon: Icons.medication_outlined, label: s.homeTileMedicines, onTap: () => context.go('/home/medicines'))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _Tile(icon: Icons.vaccines_outlined, label: s.homeTileVaccination, onTap: () => context.go('/home/vaccination'))),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(s.dataNote, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

class _GuestCard extends StatelessWidget {
  const _GuestCard({required this.s});

  final S s;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.homeGuestCardTitle, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              Text(s.loginRequiredBody, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(onPressed: () => context.go('/login?from=%2Fhome%2Froute'), child: Text(s.loginButton)),
            ],
          ),
        ),
      );
}

/// Ответ врача сверху: «Врач предложил Достар Мед» с «Посмотреть» — ведёт в «Мой путь», где есть «Понятно».
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.decision});

  final RouteDecision decision;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Card(
      color: colors.accentSoft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.md),
        child: Row(
          children: [
            Icon(Icons.medical_services_outlined, color: colors.accent),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                decision.kind == RouteCodes.redirect ? s.doctorProposed(shortOrgName(decision.toMoName)) : s.doctorKept,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(onPressed: () => context.go('/home/route'), child: Text(s.view)),
          ],
        ),
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.state, required this.onRetry, required this.onStillWaiting});

  final LoadState<PatientRoute> state;
  final VoidCallback onRetry;
  final VoidCallback onStillWaiting;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    return switch (state) {
      Loading<PatientRoute>() => const Skeleton(height: 200, radius: AppRadius.md),
      Failed<PatientRoute>(:final error) => Card(child: Padding(padding: const EdgeInsets.all(AppSpacing.sm), child: ErrorBox(error: error, onRetry: onRetry))),
      Loaded<PatientRoute>(data: final route) => Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => context.go('/home/route'),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.homeMyHospitalization, style: theme.textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.xs),
                  OrgName(route.organization.moName, prefix: '${route.organization.profileName} · ', maxLines: 2),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      StatusChip(s.stageLabel(route.stage), tone: route.stage == RouteCodes.dateAssigned ? StatusTone.accent : StatusTone.neutral),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: StageStepper(stages: route.timeline, compact: true)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      Expanded(child: Text(s.nineOfTenShort(days(route.forecast.p90Days)), style: theme.textTheme.titleMedium?.merge(AppType.numeric))),
                      const SizedBox(width: AppSpacing.sm),
                      OriginTag(route.forecast.fromModel ? Origin.ml : Origin.formula),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _WhatNow(route: route, onStillWaiting: onStillWaiting),
                ],
              ),
            ),
          ),
        ),
    };
  }
}

/// Строка «что сейчас»: дата назначена · ждём дату · запрос отправлен; при валидации — вопрос и «Да, жду».
class _WhatNow extends StatelessWidget {
  const _WhatNow({required this.route, required this.onStillWaiting});

  final PatientRoute route;
  final VoidCallback onStillWaiting;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    if (route.validationDue) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(s.validationShort, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: AppSpacing.sm),
          FilledButton(onPressed: onStillWaiting, child: Text(s.validationStill)),
          TextButton(onPressed: () => context.go('/home/route'), child: Text(s.otherAnswer)),
        ],
      );
    }
    final planned = route.dates.plannedAt;
    final line = route.openRequest != null
        ? s.requestPendingLine
        : route.stage == RouteCodes.dateAssigned && planned != null
            ? s.dateAssignedOn(dateShort(planned))
            : route.stage == RouteCodes.waitlisted
                ? s.waitingForDate
                : s.stageLabel(route.stage);
    return Row(
      children: [
        Icon(Icons.arrow_forward, size: 18, color: colors.accent),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(line, style: theme.textTheme.bodyMedium?.merge(AppType.numeric), maxLines: 2, overflow: TextOverflow.ellipsis)),
        Icon(Icons.chevron_right, color: colors.muted),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: colors.accent, size: 28),
              const SizedBox(height: AppSpacing.sm),
              Text(label, style: Theme.of(context).textTheme.labelMedium, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

/// Гостю: погода на сегодня и завтра по столице региона с бытовыми советами и новости о здравоохранении.
/// Вошедшему этот блок не показывается — у него на главной маршрут. Любой сбой источника — подпись, не ошибка.
class _DailyCards extends StatefulWidget {
  const _DailyCards({required this.regionKato});

  final String regionKato;

  @override
  State<_DailyCards> createState() => _DailyCardsState();
}

class _DailyCardsState extends State<_DailyCards> {
  LoadState<Daily> _state = const Loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _DailyCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.regionKato != widget.regionKato) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _state = const Loading());
    try {
      final daily = await context.read<Session>().api.daily(regionKato: widget.regionKato);
      if (mounted) {
        setState(() => _state = Loaded(daily));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    return switch (_state) {
      Loading() => const ListSkeleton(count: 2, itemHeight: 140),
      Failed() => Card(child: Padding(padding: const EdgeInsets.all(AppSpacing.lg), child: Text(s.weatherUnavailable, style: theme.textTheme.bodySmall))),
      Loaded<Daily>(data: final d) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WeatherCard(daily: d),
            const SizedBox(height: AppSpacing.md),
            _NewsCard(daily: d),
          ],
        ),
    };
  }
}

class _WeatherCard extends StatelessWidget {
  const _WeatherCard({required this.daily});

  final Daily daily;

  static IconData _icon(String code) => switch (code) {
        'clear' => Icons.wb_sunny_outlined,
        'fog' => Icons.foggy,
        'rain' => Icons.water_drop_outlined,
        'snow' => Icons.ac_unit,
        'thunder' => Icons.thunderstorm_outlined,
        _ => Icons.cloud_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.weatherTitle(daily.capital), style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            if (!daily.weatherAvailable)
              Text(s.weatherUnavailable, style: theme.textTheme.bodySmall)
            else ...[
              Row(
                children: [
                  for (var i = 0; i < daily.days.length && i < 2; i++) ...[
                    if (i > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(border: Border.all(color: colors.hairline), borderRadius: BorderRadius.circular(AppRadius.md)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${i == 0 ? s.today : s.tomorrow} · ${dateShort(daily.days[i].date)}', style: theme.textTheme.labelSmall),
                            const SizedBox(height: AppSpacing.xs),
                            Row(
                              children: [
                                Icon(_icon(daily.days[i].code), color: colors.accent, size: 22),
                                const SizedBox(width: AppSpacing.xs),
                                Text('${daily.days[i].tMax.round()}°', style: theme.textTheme.headlineSmall?.merge(AppType.numeric)),
                                Text(' / ${daily.days[i].tMin.round()}°', style: theme.textTheme.bodyMedium?.merge(AppType.numeric).copyWith(color: colors.muted)),
                              ],
                            ),
                            Text('${s.weatherWord(daily.days[i].code)} · ${s.precip(daily.days[i].precipitationProbability)}', style: theme.textTheme.labelSmall, maxLines: 2),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              for (final tip in daily.tips)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: '${tip.day == 0 ? s.today : s.tomorrow}: ', style: theme.textTheme.labelSmall?.copyWith(color: colors.muted)),
                    TextSpan(text: tip.text, style: theme.textTheme.bodySmall),
                  ])),
                ),
              const SizedBox(height: AppSpacing.xs),
              Text(s.weatherNote(daily.weatherSource), style: theme.textTheme.labelSmall?.copyWith(color: colors.muted)),
            ],
          ],
        ),
      ),
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.daily});

  final Daily daily;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.newsTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            if (!daily.newsAvailable || daily.news.isEmpty)
              Text(s.newsUnavailable, style: theme.textTheme.bodySmall)
            else
              for (final n in daily.news)
                InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: () => launchUrl(Uri.parse(n.url), mode: LaunchMode.externalApplication),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.title, style: theme.textTheme.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
                        Text('${n.source}${n.publishedAt != null ? ' · ${dateShort(n.publishedAt!)}' : ''}', style: theme.textTheme.labelSmall?.copyWith(color: colors.muted)),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}
