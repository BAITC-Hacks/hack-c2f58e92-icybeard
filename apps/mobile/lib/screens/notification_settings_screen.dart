import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../config/env.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/service_status_notifier.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/app_card.dart';
import '../widgets/external_link.dart';
import '../widgets/load_state_view.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/status_chip.dart';

/// Уведомления из профиля: каналы доставки поверх `GET /me/notifications`. «В приложении» работает всегда; почта,
/// SMS и push — переключатели, которые доступны, только когда сервис работает (`GET /public/service-status`). Пока
/// сервис не работает, переключатель выключен и подписан причиной («Сервис ещё не подключён», «Почтовый сервер не
/// настроен»), а сохранённое значение показывается как есть и не перезаписывается — мобилка ничего не отправляет.
/// Работающий канал меняется целиком (у всех событий, кроме закреплённого `security`) через `PUT /me/notifications`,
/// остальные настройки уходят обратно без изменений. Настройка по событиям — в веб-кабинете.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  LoadState<NotificationSettings> _state = const Loading();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_saving) {
      return; // обновление жестом во время сохранения затёрло бы его результат
    }
    setState(() => _state = const Loading());
    try {
      final settings = await context.read<Session>().api.myNotifications();
      if (mounted) {
        setState(() => _state = Loaded(settings));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  /// Переключение работающего канала: сразу на экране, после ответа — то, что записал API; ошибка — откат и сообщение.
  Future<void> _toggle(NotificationChannel channel, bool value) async {
    final before = switch (_state) { Loaded<NotificationSettings>(:final data) => data, _ => null };
    if (before == null || _saving) {
      return;
    }
    final api = context.read<Session>().api;
    final messenger = ScaffoldMessenger.of(context);
    final s = S.at(context);
    final next = before.withChannel(channel, value);
    setState(() {
      _saving = true;
      _state = Loaded(next);
    });
    try {
      final saved = await api.saveNotifications(next);
      if (mounted) {
        setState(() => _state = Loaded(saved));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _state = Loaded(before));
      }
      messenger.showSnackBar(SnackBar(content: Text(s.serverUnavailable(e))));
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final status = ServiceStatusNotifier.watch(context);
    return PageScaffold(
      title: s.notificationsRow,
      neutralBack: true,
      onRefresh: _load,
      children: [
        LoadStateView<NotificationSettings>(
          state: _state,
          onRetry: _load,
          skeleton: const CardSkeleton(height: 260),
          builder: (_, settings) => _ChannelsCard(settings: settings, status: status, busy: _saving, onChanged: _toggle),
        ),
        if (!status.anyExternalChannelUp) Text(s.onlyInAppNote, key: const ValueKey('only-in-app'), style: theme.textTheme.bodySmall),
        if (!(status.email.isUp && status.sms.isUp && status.push.isUp)) Text(s.storedPrefsKeptNote, style: theme.textTheme.labelSmall),
        Align(
          alignment: Alignment.centerLeft,
          child: ArrowLink(s.perEventInWeb, onTap: () => openExternal(context, Uri.parse('${Env.webBase}/account/notifications'))),
        ),
      ],
    );
  }
}

/// Карточка «Каналы доставки»: строка «В приложении» с чипом «работает» и три строки с переключателями.
class _ChannelsCard extends StatelessWidget {
  const _ChannelsCard({required this.settings, required this.status, required this.busy, required this.onChanged});

  final NotificationSettings settings;
  final ServiceStatus status;
  final bool busy;
  final void Function(NotificationChannel channel, bool value) onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final colors = AppPalette.of(context);
    Icon icon(IconData data) => Icon(data, size: 20, color: colors.ink);
    return AppCard(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CardLabel(s.channelsLabel),
          ListRow(
            leading: icon(Icons.notifications_none),
            title: s.channelInApp,
            trailing: StatusChip(s.channelWorks, tone: StatusTone.ok),
          ),
          for (final (i, (channel, title, glyph, service)) in [
            (NotificationChannel.email, s.channelEmail, Icons.mail_outline, status.email),
            (NotificationChannel.sms, s.channelSms, Icons.sms_outlined, status.sms),
            (NotificationChannel.push, s.channelPush, Icons.phone_iphone, status.push),
          ].indexed)
            MergeSemantics(
              child: ListRow(
                key: ValueKey('channel-${channel.name}'),
                leading: icon(glyph),
                title: title,
                subtitle: s.serviceState(service),
                last: i == 2,
                trailing: Switch(
                  value: settings.enabled(channel),
                  // пока сервис не работает (или статус неизвестен), сохранённое значение только показывается
                  onChanged: service.isUp && !busy ? (value) => onChanged(channel, value) : null,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
