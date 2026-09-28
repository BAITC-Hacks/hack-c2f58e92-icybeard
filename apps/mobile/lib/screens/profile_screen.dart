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
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/format.dart';
import '../widgets/origin_tag.dart';
import '../widgets/picker_sheet.dart';
import '../widgets/section.dart';
import '../widgets/status_chip.dart';

/// Профиль по доске M-Profile: аватар-круг, имя, «ИИН •••• 4321» (только маской, никогда полностью; без «из eGov» —
/// вход через eGov недоступен, ИИН приходит из учётной записи), чип роли; строки Язык, Регион, Уведомления
/// (экран каналов доставки, подпись «только в приложении», пока почта, SMS и push не работают), Данные и согласия
/// (как считаются прогнозы + подпись о данных), «Безопасность» (M-Account-Security), «Выйти» critical-текстом; внизу версия и подпись данных.
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

  void _sheet(Widget Function(BuildContext sheet) body) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.page, 0, AppSpacing.page, AppSpacing.xxl),
          child: body(sheet),
        ),
      );

  void _showConsents() {
    final s = S.at(context);
    _sheet((sheet) {
      final theme = Theme.of(sheet);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.originsTitle, style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Text(s.originsBody, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.lg),
          for (final (origin, note) in [(Origin.ml, s.originMlNote), (Origin.formula, s.originFormulaNote), (Origin.ai, s.originAiNote)])
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OriginTag(origin),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(note, style: theme.textTheme.bodySmall)),
                ],
              ),
            ),
          Text(s.consentsBody, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          Text(s.dataNote, style: theme.textTheme.labelSmall),
        ],
      );
    });
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
    final colors = AppPalette.of(context);
    final regionName = _regions.where((r) => r.kato == session.region).map((r) => r.name).firstOrNull ?? session.region;
    final roleKey = session.primaryRoleKey;
    final role = roleKey == null ? (session.isDoctor ? s.roleDoctor : s.roleCitizen) : s.roleTitle(roleKey);
    final profilePath = session.isDoctor ? '/doctor/profile' : '/profile';
    final onlyInApp = !ServiceStatusNotifier.watch(context).anyExternalChannelUp;
    final identity = session.iin != null ? '${s.iinLabel} ${maskIin(session.iin)}' : regionName;
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
                padding: const EdgeInsets.fromLTRB(0, AppSpacing.xs, 0, AppSpacing.lg),
                decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.hairline))),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: colors.neutralSoft),
                      child: Icon(Icons.person_outline, color: colors.ink),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(session.username ?? '', style: theme.textTheme.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text(identity, style: theme.textTheme.bodySmall?.merge(AppType.numeric), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    StatusChip(role, tone: StatusTone.neutral),
                  ],
                ),
              ),
              ListRow(title: s.languageLabel, trailing: RowValue(s.languageName(session.locale), size: 15), onTap: _pickLanguage),
              ListRow(
                title: s.regionLabel,
                trailing: RowValue(session.regionFromAccount ? '$regionName · ${s.regionFromAccount}' : regionName, size: 15),
                onTap: session.regionFromAccount || _regions.isEmpty ? null : _pickRegion,
              ),
              ListRow(title: s.notificationsRow, subtitle: onlyInApp ? s.onlyInAppShort : null, onTap: () => context.go('$profilePath/notifications')),
              ListRow(title: s.dataConsents, onTap: _showConsents),
              ListRow(title: s.securityTitle, onTap: () => context.go('$profilePath/security')),
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
