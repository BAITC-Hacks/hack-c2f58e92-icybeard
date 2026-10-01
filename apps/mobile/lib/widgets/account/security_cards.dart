import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../app_card.dart';
import '../format.dart';
import '../status_chip.dart';
import 'account_api.dart';

/// Карточки экрана «Безопасность» (доска M-Account-Security, веб `SecurityView.vue`): вход (пароль, SMS,
/// приложение-аутентификатор, резервные коды), устройства (сеансы) и последние входы. Действия — у экрана.

const _listPadding = EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs);

/// Карточка «Вход»: пароль «изменён N дн. назад» и «Сменить»; SMS-кода нет («Сервис ещё не подключён»);
/// аутентификатор — чип «настроено / не настроено» и «Настроить» или «Перенастроить» (оба — `CONFIGURE_TOTP` в
/// браузере); резервные коды — «нет в системе входа» или «кодов: N».
class SignInCard extends StatelessWidget {
  const SignInCard({super.key, required this.details, required this.onChangePassword, required this.onConfigureOtp});

  final SecurityDetails details;
  final VoidCallback onChangePassword;
  final VoidCallback onConfigureOtp;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final colors = AppPalette.of(context);
    final info = details.info;
    final age = info.passwordAgeDays(DateTime.now());
    final codes = details.recoveryCodes;
    Icon icon(IconData data) => Icon(data, size: 20, color: colors.ink);
    return AppCard(
      padding: _listPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.securitySignIn),
          ListRow(
            leading: icon(Icons.lock_outline),
            title: s.passwordRow,
            subtitle: age == null ? s.passwordChangedUnknown : s.passwordChanged(age),
            trailing: Text(s.changePassword, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colors.accentHover)),
            onTap: onChangePassword,
          ),
          // SMS-шлюза нет: подпись «Сервис ещё не подключён», как у каналов уведомлений, а не чип «включено»
          ListRow(leading: icon(Icons.sms_outlined), title: s.methodSms, subtitle: s.smsNotConnected),
          ListRow(
            leading: icon(Icons.phone_iphone),
            title: s.authenticatorApp,
            subtitle: info.otpConfigured ? s.reconfigure : s.configure,
            trailing: StatusChip(info.otpConfigured ? s.configured : s.notConfigured, tone: info.otpConfigured ? StatusTone.ok : StatusTone.neutral),
            // действие названо подстрокой («Настроить» / «Перенастроить»), шеврон лишь отнял бы место у названия
            chevron: false,
            onTap: onConfigureOtp,
          ),
          ListRow(
            leading: icon(Icons.password),
            title: s.recoveryCodesRow,
            subtitle: codes == null ? s.noRecoveryCodes : s.recoveryCodesLeft(codes.length),
            last: true,
          ),
        ],
      ),
    );
  }
}

/// Карточка «Устройства»: текущий сеанс сверху с чипом «это устройство», остальные — с «Завершить»; пока действие в
/// полёте ([busy]), кнопки заблокированы.
class DevicesCard extends StatelessWidget {
  const DevicesCard({super.key, required this.sessions, required this.busy, required this.onEnd});

  final List<DeviceSession> sessions;
  final bool busy;
  final ValueChanged<DeviceSession> onEnd;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final ordered = [...sessions]..sort((a, b) => (b.current ? 1 : 0) - (a.current ? 1 : 0));
    return AppCard(
      padding: _listPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.devicesSection),
          if (ordered.every((d) => d.current))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(s.noOtherSessions, style: Theme.of(context).textTheme.bodySmall),
            ),
          for (final (i, d) in ordered.indexed)
            ListRow(
              title: [d.device ?? s.unknownDevice, ?d.browser].join(' · '),
              strong: true,
              subtitle: [?d.ip, if (d.lastAccess != null) dateTimeShort(d.lastAccess)].join(' · '),
              last: i == ordered.length - 1,
              trailing: d.current
                  ? StatusChip(s.thisDevice, tone: StatusTone.accent)
                  : OutlinedButton(style: AppButtons.danger(context, small: true), onPressed: busy ? null : () => onEnd(d), child: Text(s.endSession)),
            ),
        ],
      ),
    );
  }
}

/// Карточка «Последние входы» (веб `account.security.recentLogins`): дата и время, способ входа словами (незнакомый —
/// как прислал сервер) и IP, чип «успешно» / «не удалось».
class RecentLoginsCard extends StatelessWidget {
  const RecentLoginsCard({super.key, required this.logins});

  final List<LoginRecord> logins;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return AppCard(
      padding: _listPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.recentLoginsTitle),
          if (logins.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(s.noLoginsYet, style: Theme.of(context).textTheme.bodySmall),
            ),
          for (final (i, login) in logins.indexed)
            ListRow(
              title: dateTimeShort(login.at),
              subtitle: [s.signInMethod(login.method), ?login.ip].join(' · '),
              trailing: StatusChip(login.success ? s.signInOk : s.signInFailed, tone: login.success ? StatusTone.ok : StatusTone.warn),
              last: i == logins.length - 1,
            ),
        ],
      ),
    );
  }
}
