import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/service_status_notifier.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/account/personal_data_sheet.dart';
import '../widgets/account/profile_head.dart';
import '../widgets/app_card.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/format.dart';
import '../widgets/picker_sheet.dart';
import '../widgets/section.dart';

/// Профиль обоих кабинетов (`/profile`, `/doctor/profile`; веб `ProfileView.vue` и меню аккаунта, IA 13.2): шапка —
/// имя, роль (у сотрудника с больницей), ИИН только маской, строка о недоступном eGov; строки «Личные данные» (лист,
/// `PUT /me/profile`), «Язык» (настройка устройства — решение Q11, в учётную запись не пишется), «Регион» (только
/// без региона в учётной записи), «Уведомления», «Данные и согласия», «Безопасность», «Откуда берутся цифры»,
/// «Выйти»; внизу версия и подпись данных.
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
    if (!context.read<Session>().regionFromAccount) {
      _loadRegions();
    }
  }

  /// Справочник регионов — только для строки «Регион»; без него строка показывает код и не открывается.
  Future<void> _loadRegions() async {
    try {
      final regions = await context.read<Session>().api.regions();
      if (mounted) {
        setState(() => _regions = regions);
      }
    } on Exception {
      // строка «Регион» покажет код региона и останется без выбора
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
    }
  }

  Future<void> _personal() async {
    final messenger = ScaffoldMessenger.of(context);
    final saved = S.at(context).savedToast;
    if (await showPersonalDataSheet(context)) {
      messenger.showSnackBar(SnackBar(content: Text(saved)));
    }
  }

  Future<void> _logout() async {
    await context.read<Session>().logout();
    if (mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final status = ServiceStatusNotifier.watch(context);
    final regionName = _regions.where((r) => r.kato == session.region).map((r) => r.name).firstOrNull ?? session.region;
    final roleKey = session.primaryRoleKey;
    final role = roleKey == null ? (session.isDoctor ? s.roleDoctor : s.roleCitizen) : s.roleTitle(roleKey);
    final org = session.organizationName;
    final roleLine = [role, if (org != null) shortOrgName(org), if (org != null) ?session.moCode].join(' · ');
    final iin = session.me?.iinMasked ?? (session.iin == null ? null : maskIin(session.iin));
    final profilePath = session.isDoctor ? '/doctor/profile' : '/profile';
    return PageScaffold(
      title: s.profileTitle,
      leading: const DarumenMark(size: 28),
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
                child: ProfileHead(name: session.displayName ?? session.username ?? '', roleLine: roleLine, iinMasked: iin, egovOff: !status.egov.isUp),
              ),
              ListRow(title: s.personalTitle, subtitle: session.email, onTap: _personal),
              ListRow(title: s.languageLabel, trailing: RowValue(s.languageName(session.locale)), onTap: _pickLanguage),
              if (!session.regionFromAccount)
                ListRow(title: s.regionLabel, trailing: RowValue(regionName), onTap: _regions.isEmpty ? null : _pickRegion),
              ListRow(
                title: s.notificationsRow,
                subtitle: status.anyExternalChannelUp ? null : s.onlyInAppShort,
                onTap: () => context.go('$profilePath/notifications'),
              ),
              ListRow(title: s.consentsTitle, onTap: () => context.go('$profilePath/consents')),
              ListRow(title: s.securityTitle, onTap: () => context.go('$profilePath/security')),
              ListRow(title: s.forecastsTitle, onTap: () => showForecastsSheet(context)),
              ListRow(
                title: s.logout,
                strong: true,
                titleColor: colors.danger,
                last: true,
                chevron: false,
                trailing: Icon(Icons.logout, size: 20, color: colors.danger),
                onTap: _logout,
              ),
            ],
          ),
        ),
        FutureBuilder<PackageInfo>(
          future: PackageInfo.fromPlatform(),
          builder: (_, snapshot) => Text(
            [
              if (snapshot.hasData) s.appVersion('${snapshot.data!.version} (${snapshot.data!.buildNumber})'),
              s.dataNote,
            ].join(' · '),
            style: theme.textTheme.labelSmall,
          ),
        ),
      ],
    );
  }
}
