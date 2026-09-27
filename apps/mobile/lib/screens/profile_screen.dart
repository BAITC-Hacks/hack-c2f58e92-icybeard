import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/format.dart';
import '../widgets/origin_tag.dart';
import '../widgets/picker_sheet.dart';
import '../widgets/section.dart';
import '../widgets/status_chip.dart';

/// Профиль: имя или логин с чипом роли и регионом, строки-значения (ИИН маской — никогда полностью, язык, регион),
/// «Справочно» (как считаются прогнозы, вакцинация, журнал решений для врача), «Выйти» внизу, версия и подпись
/// данных. ИИН показывается только маской. Адреса API — только сборкой (config/env.dart).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Region> _regions = const [];

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    try {
      final regions = await context.read<Session>().api.regions();
      if (mounted) {
        setState(() => _regions = regions);
      }
    } catch (_) {
      // регион покажем кодом
    }
  }

  Future<void> _pickLanguage() async {
    final session = context.read<Session>();
    final s = S.at(context);
    final chosen = await PickerSheet.show<String>(
      context,
      title: s.languageLabel,
      items: [PickerItem('ru', s.languageName('ru')), PickerItem('kk', s.languageName('kk'))],
      selected: session.locale,
      search: false,
    );
    if (chosen != null) {
      await session.setLocale(chosen);
    }
  }

  Future<void> _pickRegion() async {
    final session = context.read<Session>();
    final s = S.at(context);
    final chosen = await PickerSheet.show<String>(
      context,
      title: s.regionLabel,
      items: [for (final r in _regions) PickerItem(r.kato, r.name)],
      selected: session.region,
    );
    if (chosen != null) {
      await session.setRegion(chosen);
      if (mounted) {
        setState(() {});
      }
    }
  }

  void _showOrigins() {
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
            Text(s.originsTitle, style: Theme.of(sheet).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            Text(s.originsBody, style: Theme.of(sheet).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.lg),
            for (final (origin, note) in [(Origin.ml, s.originMlNote), (Origin.formula, s.originFormulaNote), (Origin.ai, s.originAiNote)])
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OriginTag(origin),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(note, style: Theme.of(sheet).textTheme.bodySmall)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final session = context.read<Session>();
    await session.logout();
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = S.at(context);
    final theme = Theme.of(context);
    final regionName = _regions.where((r) => r.kato == session.region).map((r) => r.name).firstOrNull ?? session.region;
    final role = session.isDoctor ? s.roleDoctor : s.roleCitizen;
    return PageScaffold(
      title: s.profileTitle,
      children: [
        Row(
          children: [
            Expanded(child: Text(session.username ?? '', style: theme.textTheme.headlineSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const SizedBox(width: AppSpacing.sm),
            StatusChip(role, tone: StatusTone.accent),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(regionName, style: theme.textTheme.bodySmall),
        const SizedBox(height: AppSpacing.lg),
        Card(
          child: Column(
            children: [
              if (session.iin != null) ...[
                _ValueRow(label: s.iinLabel, value: '${maskIin(session.iin)} · ${s.regionFromAccount}'),
                const Divider(),
              ],
              _ValueRow(label: s.languageLabel, value: s.languageName(session.locale), onTap: _pickLanguage),
              const Divider(),
              _ValueRow(
                label: s.regionLabel,
                value: session.regionFromAccount ? '$regionName · ${s.regionFromAccount}' : regionName,
                onTap: session.regionFromAccount || _regions.isEmpty ? null : _pickRegion,
              ),
            ],
          ),
        ),
        SectionTitle(s.referenceSection),
        Card(
          child: Column(
            children: [
              _ValueRow(label: s.originsTitle, onTap: _showOrigins),
              const Divider(),
              _ValueRow(label: s.vaccinationTitle, onTap: () => context.go('/home/vaccination')),
              if (session.isDoctor) ...[
                const Divider(),
                _ValueRow(label: s.decisionsTitle, onTap: () => context.go('/doctor/referral/decisions')),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        OutlinedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout), label: Text(s.logout)),
        const SizedBox(height: AppSpacing.lg),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (_, snapshot) => Text(
            snapshot.hasData ? s.appVersion('${snapshot.data!.version} (${snapshot.data!.buildNumber})') : '',
            style: theme.textTheme.labelSmall,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(s.dataNote, style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
      ],
    );
  }
}

/// Строка «Метка … Значение ›»: значение справа, шеврон — если есть действие.
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, this.value, this.onTap});

  final String label;
  final String? value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return ListTile(
      title: Text(label, style: theme.textTheme.bodyMedium),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (value != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180),
              child: Text(value!, style: theme.textTheme.bodyMedium?.copyWith(color: colors.muted), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end),
            ),
          if (onTap != null) Icon(Icons.chevron_right, color: colors.muted),
        ],
      ),
      onTap: onTap,
    );
  }
}
