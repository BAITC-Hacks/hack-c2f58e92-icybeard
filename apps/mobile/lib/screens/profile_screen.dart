import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../widgets/format.dart';
import '../widgets/section.dart';
import '../widgets/status_chip.dart';

/// Профиль вместо экрана настроек: кто вошёл, ИИН маской, регион из учётной записи, язык, справочные ссылки, выход.
/// Адреса API и Keycloak здесь не редактируются — они задаются сборкой (`--dart-define`, см. config/env.dart).
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

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = S.at(context);
    final theme = Theme.of(context);
    final regionName = _regions.where((r) => r.kato == session.region).map((r) => r.name).firstOrNull ?? session.region;
    return PageScaffold(
      title: s.profileTitle,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(session.username ?? s.guest, style: theme.textTheme.titleLarge)),
                    StatusChip(
                      switch (session.role) { AuthRole.doctor => s.roleDoctor, AuthRole.citizen => s.roleCitizen, AuthRole.guest => s.guest },
                      tone: session.isAuthenticated ? StatusTone.accent : StatusTone.neutral,
                    ),
                  ],
                ),
                if (session.iin != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('${s.iinLabel} ${maskIin(session.iin)}', style: theme.textTheme.bodyMedium),
                ],
                const SizedBox(height: AppSpacing.sm),
                Text(
                  '${s.regionLabel}: $regionName${session.regionFromAccount ? ' · ${s.regionFromAccount}' : ''}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
        SectionTitle(s.languageLabel),
        SegmentedButton<String>(
          segments: const [ButtonSegment(value: 'ru', label: Text('РУС')), ButtonSegment(value: 'kk', label: Text('ҚАЗ'))],
          selected: {session.locale},
          onSelectionChanged: (v) => session.setLocale(v.first),
        ),
        SectionTitle(s.referenceSection),
        Card(
          child: Column(
            children: [
              ListTile(
                title: Text(s.vaccinationTitle),
                subtitle: Text(s.vaccinationSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/home/vaccination'),
              ),
              if (session.isDoctor) ...[
                const Divider(),
                ListTile(
                  title: Text(s.decisionsTitle),
                  subtitle: Text(s.decisionsSubtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/doctor/referral/decisions'),
                ),
              ],
              const Divider(),
              ListTile(title: Text(s.modelQualityNote, style: theme.textTheme.bodySmall), leading: const Icon(Icons.verified_outlined)),
              const Divider(),
              ListTile(title: Text(s.trustedContactsRoadmap, style: theme.textTheme.bodySmall), leading: const Icon(Icons.schedule_outlined)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (session.isAuthenticated)
          OutlinedButton.icon(onPressed: () => _logout(context), icon: const Icon(Icons.logout), label: Text(s.logout))
        else
          FilledButton(onPressed: () => context.go('/login'), child: Text(s.loginButton)),
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

  Future<void> _logout(BuildContext context) async {
    final session = context.read<Session>();
    await session.logout();
    if (context.mounted) {
      context.go('/home');
    }
  }
}
