import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import '../widgets/error_box.dart';
import '../widgets/format.dart';
import '../widgets/origin_tag.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// Главная гражданина по образцу NHS App: сверху карточка «Моя госпитализация» (или приглашение войти), ниже три
/// плитки-существительных. Никаких новостей, баннеров и демо-подписей.
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

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final session = context.watch<Session>();
    final theme = Theme.of(context);
    return PageScaffold(
      title: s.navHome,
      onRefresh: session.isAuthenticated ? _load : null,
      children: [
        if (!session.isAuthenticated) _GuestCard(s: s) else _RouteCard(state: _state, s: s, onRetry: _load),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(child: _Tile(icon: Icons.schedule_outlined, label: s.homeTileWait, onTap: () => context.go('/home/wait'))),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: _Tile(icon: Icons.medication_outlined, label: s.homeTileMedicines, onTap: () => context.go('/home/medicines'))),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(child: _Tile(icon: Icons.vaccines_outlined, label: s.homeTileVaccination, onTap: () => context.go('/home/vaccination'))),
            const SizedBox(width: AppSpacing.sm),
            const Expanded(child: SizedBox.shrink()),
          ],
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

class _RouteCard extends StatelessWidget {
  const _RouteCard({required this.state, required this.s, required this.onRetry});

  final LoadState<PatientRoute> state;
  final S s;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return switch (state) {
      Loading<PatientRoute>() => const Skeleton(height: 160, radius: AppRadius.md),
      Failed<PatientRoute>(:final error) => ErrorBox(error: error, onRetry: onRetry),
      Loaded<PatientRoute>(data: final route) => Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: () => context.go('/home/route'),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.homeMyHospitalization, style: theme.textTheme.titleMedium)),
                      OriginTag(route.forecast.fromModel ? Origin.ml : Origin.formula),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text('${route.organization.profileName} · ${route.organization.moName}', style: theme.textTheme.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      StatusChip(s.stageLabel(route.stage), tone: route.stage == RouteCodes.dateAssigned ? StatusTone.accent : StatusTone.neutral),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(s.waitingFor(route.daysWaiting), style: theme.textTheme.bodySmall?.merge(AppType.numeric))),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(s.nineOfTen(days(route.forecast.p90Days)), style: theme.textTheme.bodyLarge?.merge(AppType.numeric)),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          route.expiredChecklistCount > 0 ? s.checklistExpiredCount(route.expiredChecklistCount) : s.checklistAllValid,
                          style: theme.textTheme.bodySmall?.copyWith(color: route.expiredChecklistCount > 0 ? colors.danger : colors.ok),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: colors.muted),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
    };
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
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: colors.accent),
              const SizedBox(height: AppSpacing.md),
              Text(label, style: Theme.of(context).textTheme.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}
