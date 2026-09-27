import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/env.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/circle_button.dart';
import '../widgets/darumen_mark.dart';
import '../widgets/empty_state.dart';
import '../widgets/external_link.dart';

/// «Кабинет доступен в веб-версии» — для ролей без мобильного кабинета (регулятор, стюард данных, аудитор,
/// администратор организации без рабочего списка): кто вошёл и с какой ролью, «Открыть веб» (браузер, Env.webBase)
/// и «Выйти». Никаких данных кабинета в приложении не показывается.
class WebOnlyScreen extends StatelessWidget {
  const WebOnlyScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    await context.read<Session>().logout();
    if (context.mounted) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final session = context.watch<Session>();
    final role = session.primaryRoleKey;
    final roleName = role == null ? s.cabinet : s.roleTitle(role);
    final who = session.displayName ?? session.username ?? '';
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.md),
              child: Row(children: [const HomeMarkAnchor(), const Spacer(), const LanguageButton()]),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xl, AppSpacing.page, AppSpacing.xl),
                children: [
                  EmptyState(
                    icon: Icons.desktop_windows_outlined,
                    tone: AppTones.of(context).accent,
                    title: s.webOnlyTitle,
                    body: s.webOnlyBody(roleName),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (who.isNotEmpty) Text('$who · $roleName', style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
                  const SizedBox(height: AppSpacing.xs),
                  Text(Env.webBase, style: theme.textTheme.labelSmall, textAlign: TextAlign.center),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                      onPressed: () => openExternal(context, Uri.parse('${Env.webBase}/')),
                      icon: const Icon(Icons.open_in_new, size: 20),
                      label: Text(s.openWeb),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(onPressed: () => _logout(context), child: Text(s.logout)),
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
