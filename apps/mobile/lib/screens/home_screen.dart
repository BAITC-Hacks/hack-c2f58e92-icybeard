import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/app_card.dart';
import '../widgets/circle_button.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/error_box.dart';
import '../widgets/format.dart';
import '../widgets/hero_number.dart';
import '../widgets/org_name.dart';
import '../widgets/origin_tag.dart';
import '../widgets/section.dart';
import '../widgets/signal_card.dart';
import '../widgets/skeleton.dart';
import '../widgets/stage_stepper.dart';
import '../widgets/status_chip.dart';

/// Главная гражданина по доске M-Home: карточка «Моя госпитализация» с hero «до N дн. до госпитализации»
/// (N — 9 из 10 таких пациентов, p90), подписью «профиль · организация», прогрессом этапов, чипом происхождения и
/// ссылкой «Открыть маршрут»; ниже карточка-сигнал «Врач предложил …» с подстрокой «Там ждут на X дней меньше»;
/// три плитки и подпись о данных. Погоды и новостей на главной нет. Экран открыт только после входа.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  LoadState<PatientRoute> _state = const Loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<Session>();
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
    final route = switch (_state) { Loaded<PatientRoute>(:final data) => data, _ => null };
    final answer = route?.latestDecision;
    final unseen = answer != null && answer.decisionId != session.seenDecisionId;
    return PageScaffold(
      title: s.navHome,
      hero: true,
      leading: const HomeMarkAnchor(),
      actions: const [LanguageButton()],
      onRefresh: _load,
      children: [
        _RouteCard(state: _state, onRetry: _load, onStillWaiting: _stillWaiting),
        if (route != null && unseen) _AnswerCard(route: route, decision: answer),
        const _Tiles(),
        Text(s.dataNote, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// Карточка-сигнал: «Врач предложил Достар Мед · Там ждут на 12 дн. меньше →». Разница считается из прогноза текущей
/// организации (p50) и p50 предложенной из списка альтернатив; если её там нет — причина врача или дата.
class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.route, required this.decision});

  final PatientRoute route;
  final RouteDecision decision;

  String? _subtitle(S s) {
    if (decision.kind == RouteCodes.redirect) {
      final proposed = route.alternatives.where((a) => a.moCode == decision.toMoCode).firstOrNull;
      final fewer = proposed == null ? 0 : (route.forecast.p50Days - proposed.p50Days).round();
      if (fewer > 0) {
        return s.fewerDays(fewer);
      }
    }
    final reason = decision.reason;
    return reason != null && reason.isNotEmpty ? '«$reason»' : dateTimeShort(decision.recordedAt);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return SignalCard(
      title: decision.kind == RouteCodes.redirect ? s.doctorProposed(shortOrgName(decision.toMoName)) : s.doctorKept,
      subtitle: _subtitle(s),
      onTap: () => context.go('/home/route'),
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
      Loading<PatientRoute>() => const CardSkeleton(height: 260),
      Failed<PatientRoute>(:final error) => ErrorBox(error: error, onRetry: onRetry),
      Loaded<PatientRoute>(data: final route) => AppCard(
          onTap: () => context.go('/home/route'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CardLabel(
                s.homeMyHospitalization,
                trailing: StatusChip(s.stageLabel(route.stage), tone: route.stage == RouteCodes.dateAssigned ? StatusTone.ok : StatusTone.neutral),
              ),
              const SizedBox(height: 14),
              HeroNumber(value: s.heroUntil(days(route.forecast.p90Days)).$1, unit: s.heroUntil(days(route.forecast.p90Days)).$2),
              const SizedBox(height: 14),
              OrgName(route.organization.moName, prefix: '${route.organization.profileName} · ', maxLines: 2, style: theme.textTheme.bodySmall),
              const SizedBox(height: 14),
              StageStepper(stages: route.timeline),
              if (route.validationDue) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(child: Text(s.validationShort, style: theme.textTheme.titleSmall)),
                    TextButton(onPressed: onStillWaiting, child: Text(s.validationStill)),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  OriginTag(route.forecast.fromModel ? Origin.ml : Origin.formula),
                  const Spacer(),
                  ArrowLink(s.openRoute),
                ],
              ),
            ],
          ),
        ),
    };
  }
}

/// Три плитки: «Сколько ждут», «Лекарства» (при `medicines.check`), «Вакцинация» — белые, radius 18, иконка
/// в круге 36 surface-sunken/accent и подпись 13/700 (доска m-home-new `.tile`).
class _Tiles extends StatelessWidget {
  const _Tiles();

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final medicines = context.select<Session, bool>((x) => x.can(Perm.medicinesCheck));
    final tiles = [
      _Tile(icon: Icons.schedule_outlined, label: s.homeTileWait, onTap: () => context.go('/home/wait')),
      if (medicines) _Tile(icon: Icons.medication_outlined, label: s.homeTileMedicines, onTap: () => context.go('/home/medicines')),
      _Tile(icon: Icons.vaccines_outlined, label: s.homeTileVaccination, onTap: () => context.go('/home/vaccination')),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, tile) in tiles.indexed) ...[
            if (i > 0) const SizedBox(width: AppSpacing.md),
            Expanded(child: tile),
          ],
        ],
      ),
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
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 14),
      onTap: onTap,
      semanticsLabel: label,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(shape: BoxShape.circle, color: colors.surfaceSunken),
            child: Icon(icon, color: colors.accent, size: 20),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 13, height: 1.25),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
