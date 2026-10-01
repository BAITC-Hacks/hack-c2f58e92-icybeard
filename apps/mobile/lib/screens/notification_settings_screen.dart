import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/models.dart';
import '../config/env.dart';
import '../l10n/strings.dart';
import '../state/citizen_notifications_notifier.dart';
import '../state/load_state.dart';
import '../state/service_status_notifier.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/account/route_updates_card.dart';
import '../widgets/api_error.dart';
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
/// остальные настройки уходят обратно без изменений. Гражданину над каналами — один переключатель события «Изменения
/// моего маршрута» (канал «в системе», решение Q12): он решает, что показывает колокольчик, и пишется через
/// `withEventChannel`, не трогая настройки, сделанные в вебе; после сохранения колокольчик перечитывается. Остальная
/// настройка по событиям — в веб-кабинете. Ошибка сохранения — откат и `showApiError`.
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
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _state = Failed(e));
      }
    }
  }

  /// Гражданин (роль `citizen` с `route.own`, как у колокольчика — решение API 9) видит переключатель событий маршрута.
  static bool _citizen(Session session) => session.primaryRoleKey == 'citizen' && session.can(Perm.routeOwn);

  /// Переключение работающего канала у всех изменяемых событий.
  Future<void> _toggle(NotificationChannel channel, bool value) => _save((before) => before.withChannel(channel, value));

  /// «Изменения моего маршрута»: только канал «в системе» этого события; колокольчик после ответа перечитывается.
  Future<void> _toggleRoute(bool value) =>
      _save((before) => before.withEventChannel(NotificationSettings.routeUpdates, NotificationChannel.inApp, value), refreshBell: true);

  /// Изменение сразу на экране, после ответа — то, что записал API; ошибка — откат и сообщение.
  Future<void> _save(NotificationSettings Function(NotificationSettings before) change, {bool refreshBell = false}) async {
    final before = switch (_state) { Loaded<NotificationSettings>(:final data) => data, _ => null };
    if (before == null || _saving) {
      return;
    }
    final api = context.read<Session>().api;
    final bell = refreshBell ? context.read<CitizenNotificationsNotifier?>() : null;
    final next = change(before);
    setState(() {
      _saving = true;
      _state = Loaded(next);
    });
    try {
      final saved = await api.saveNotifications(next);
      if (mounted) {
        setState(() => _state = Loaded(saved));
      }
      // колокольчик перечитывается в фоне: его сбой не откатывает уже записанную настройку
      if (bell != null) {
        unawaited(bell.refresh());
      }
    } on Exception catch (e) {
      if (mounted) {
        setState(() => _state = Loaded(before));
        await showApiError(context, e);
      }
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
    final citizen = _citizen(context.watch<Session>());
    return PageScaffold(
      title: s.notificationsRow,
      onRefresh: _load,
      children: [
        LoadStateView<NotificationSettings>(
          state: _state,
          onRetry: _load,
          skeleton: const CardSkeleton(height: 260),
          builder: (_, settings) {
            final route = citizen ? settings.event(NotificationSettings.routeUpdates) : null;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (route != null) ...[
                  RouteUpdatesCard(key: const ValueKey('event-route_updates'), event: route, busy: _saving, onChanged: _toggleRoute),
                  const SizedBox(height: AppSpacing.md),
                ],
                _ChannelsCard(settings: settings, status: status, busy: _saving, onChanged: _toggle),
              ],
            );
          },
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
