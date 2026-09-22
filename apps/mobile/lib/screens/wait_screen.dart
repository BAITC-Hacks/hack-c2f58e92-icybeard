import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/typography.dart';
import '../widgets/empty_state.dart';
import '../widgets/error_box.dart';
import '../widgets/format.dart';
import '../widgets/kpi_tile.dart';
import '../widgets/origin_tag.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// Гражданин и гость: сколько ждут плановой госпитализации по региону и профилю (p50 / p90 / шанс за 30 дней —
/// «ML‑модель»), индекс региона и ориентир МЗ РК («формула»), где быстрее. Ничего не запрашивает, пока не выбраны
/// регион и профиль; профиль запоминается между запусками.
class WaitScreen extends StatefulWidget {
  const WaitScreen({super.key, this.regionKato, this.profileCode});

  final String? regionKato;
  final String? profileCode;

  @override
  State<WaitScreen> createState() => _WaitScreenState();
}

class _WaitData {
  const _WaitData(this.prediction, this.alternatives, this.index);

  final PredictResponse prediction;
  final List<Alternative> alternatives;
  final IndexItem? index;
}

class _WaitScreenState extends State<WaitScreen> {
  List<Region> _regions = const [];
  List<BedProfile> _profiles = const [];
  RouteBenchmark? _target;
  String? _region;
  String? _profile;
  LoadState<_WaitData>? _state;
  Object? _refdataError;

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    _region = widget.regionKato ?? session.region;
    _profile = widget.profileCode ?? session.lastProfile;
    _loadRefdata();
  }

  Future<void> _loadRefdata() async {
    final api = context.read<Session>().api;
    try {
      final results = await Future.wait<Object>([api.regions(), api.profiles(), api.routeStandard()]);
      if (!mounted) {
        return;
      }
      setState(() {
        _regions = results[0] as List<Region>;
        _profiles = results[1] as List<BedProfile>;
        _target = (results[2] as RouteStandard).target;
        _refdataError = null;
      });
      if (_profile != null && _profiles.any((p) => p.code == _profile)) {
        await _run();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _refdataError = e);
      }
    }
  }

  Future<void> _run() async {
    final session = context.read<Session>();
    final region = _region;
    final profile = _profile;
    if (region == null || profile == null) {
      return;
    }
    setState(() => _state = const Loading());
    try {
      final body = {'regionKato': region, 'profileCode': profile};
      final results = await Future.wait<Object>([session.api.predict(body), session.api.alternatives(body), session.api.index(profileCode: profile)]);
      await session.rememberProfile(profile);
      if (!session.regionFromAccount) {
        await session.setRegion(region);
      }
      if (mounted) {
        setState(() => _state = Loaded(_WaitData(
              results[0] as PredictResponse,
              results[1] as List<Alternative>,
              (results[2] as List<IndexItem>).where((i) => i.regionKato == region).firstOrNull,
            )));
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
    final state = _state;
    final ready = _region != null && _profile != null;
    return PageScaffold(
      title: s.waitTitle,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _regions.any((r) => r.kato == _region) ? _region : null,
          decoration: InputDecoration(labelText: s.regionLabel),
          isExpanded: true,
          items: [for (final r in _regions) DropdownMenuItem(value: r.kato, child: Text(r.name, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _region = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          initialValue: _profiles.any((p) => p.code == _profile) ? _profile : null,
          decoration: InputDecoration(labelText: s.profileLabel),
          isExpanded: true,
          items: [for (final p in _profiles) DropdownMenuItem(value: p.code, child: Text(p.name, overflow: TextOverflow.ellipsis))],
          onChanged: (v) => setState(() => _profile = v),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(onPressed: ready && state is! Loading ? _run : null, icon: const Icon(Icons.search), label: Text(s.findButton)),
        if (_refdataError != null) ...[const SizedBox(height: AppSpacing.md), ErrorBox(error: _refdataError, onRetry: _loadRefdata)],
        if (state == null)
          EmptyState(icon: Icons.tune, title: s.chooseRegionProfile, body: s.chooseRegionProfileBody)
        else ...[
          SectionTitle(s.avgRegionSection, origin: Origin.ml),
          switch (state) {
            Loading<_WaitData>() => const KpiRowSkeleton(),
            Failed<_WaitData>(:final error) => ErrorBox(error: error, onRetry: _run),
            Loaded<_WaitData>(:final data) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  KpiRow(
                    children: [
                      KpiTile(value: days(data.prediction.p50Days), label: s.kpiHalfWaits),
                      KpiTile(value: days(data.prediction.p90Days), label: s.kpiNineOfTen),
                      KpiTile(value: pct(data.prediction.pWithin30Days), label: s.kpiWithin30),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          data.index == null ? s.indexUnavailable : s.indexShown(data.index!.indexValue.toStringAsFixed(1), data.index!.rank),
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const OriginTag(Origin.formula),
                    ],
                  ),
                  if (_target != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(s.benchmarkLine(days(_target!.value), _target!.source), style: theme.textTheme.bodySmall),
                  ],
                  SectionTitle(s.fasterSection, origin: Origin.ml),
                  if (data.alternatives.isEmpty)
                    Text(s.noOrgsForProfile, style: theme.textTheme.bodySmall)
                  else
                    Card(
                      child: Column(
                        children: [
                          for (final a in data.alternatives)
                            ListTile(
                              title: Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Wrap(
                                spacing: AppSpacing.sm,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  StatusChip('${s.flagRefusalRisk} ${pct(a.pRefusal)}', tone: a.pRefusal > 0.2 ? StatusTone.warn : StatusTone.neutral),
                                  if (a.distanceKm > 0) Text('${a.distanceKm.round()} ${s.kmUnit}', style: theme.textTheme.bodySmall),
                                ],
                              ),
                              trailing: Text('${days(a.p50Days)} ${s.daysUnit}', style: theme.textTheme.titleMedium?.merge(AppType.numeric)),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Text(s.modelTrained(data.prediction.model.name, data.prediction.model.version, data.prediction.model.trainedThrough), style: theme.textTheme.labelSmall),
                ],
              ),
          },
        ],
      ],
    );
  }
}
