import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../l10n/strings.dart';
import '../state/load_state.dart';
import '../state/session.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/app_card.dart';
import '../widgets/citizen/leaflet_api.dart';
import '../widgets/citizen/leaflet_document.dart';
import '../widgets/empty_state.dart';
import '../widgets/external_link.dart';
import '../widgets/format.dart';
import '../widgets/origin_tag.dart';
import '../widgets/section.dart';
import '../widgets/skeleton.dart';
import '../widgets/state_view.dart';

/// «Памятка после приёма» гражданина (`/home/route/leaflet/:token`, вложен в «Мой путь», без плавающей навигации):
/// текст памятки с публичного `GET /scribe/leaflets/{token}` в разборе веба (LeafletView.vue) — номер памятки
/// (хвост токена) и язык, «утверждена {дата} · утверждена врачом», «Скопировать ссылку» и «Открыть в браузере»
/// (публичная страница веба), плашка «Что дальше», нумерованные шаги, блок «О чём вы говорили с врачом» с меткой
/// «черновик ИИ» и три строки подвала. Неизвестный или удалённый токен (403, 404, 410) — «Ссылка истекла»; сбой сети
/// и 5xx — ошибка загрузки с «Повторить». QR на своём телефоне не нужен.
class LeafletScreen extends StatefulWidget {
  const LeafletScreen({super.key, required this.token});

  /// `leafletToken` завершённой записи приёма (`GET /route/me/scribe`).
  final String token;

  @override
  State<LeafletScreen> createState() => _LeafletScreenState();
}

class _LeafletScreenState extends State<LeafletScreen> {
  LoadState<PublicLeaflet> _state = const Loading();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LeafletScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token != widget.token) {
      _load();
    }
  }

  Future<void> _load() async {
    final api = context.read<Session>().api;
    setState(() => _state = const Loading());
    LoadState<PublicLeaflet> next;
    try {
      next = Loaded(await api.publicLeaflet(widget.token));
    } on Object catch (e) {
      next = Failed(e);
    }
    if (mounted) {
      setState(() => _state = next);
    }
  }

  Future<void> _copyLink() async {
    final copied = S.at(context).myLinkCopied;
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: leafletWebLink(widget.token)));
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(copied)));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final leaflet = switch (_state) { Loaded<PublicLeaflet>(:final data) => data, _ => null };
    return PageScaffold(
      title: s.leafletTitle,
      onRefresh: _load,
      children: [
        _LeafletHead(
          token: widget.token,
          leaflet: leaflet,
          onCopy: _copyLink,
          onOpen: () => openExternal(context, Uri.parse(leafletWebLink(widget.token))),
        ),
        ...switch (_state) {
          Loading<PublicLeaflet>() => const [CardSkeleton(height: 280)],
          Failed<PublicLeaflet>(:final error) when _expired(error) => [
              EmptyState(icon: Icons.schedule, title: s.myLeafletExpiredTitle, body: s.myLeafletExpiredText),
            ],
          Failed<PublicLeaflet>(:final error) => [ErrorState(error: error, onRetry: _load)],
          Loaded<PublicLeaflet>(:final data) => [
              AppCard(child: LeafletDocument(text: data.text)),
              const _TalkedNote(),
              const _LeafletFooter(),
            ],
        },
      ],
    );
  }

  /// Чужой, удалённый или просроченный токен — веб показывает одно и то же «Ссылка истекла» без деталей.
  static bool _expired(Object error) => error is ApiException && const {403, 404, 410}.contains(error.status);
}

/// Шапка документа: «памятка F6A7B8C9 · RU», строка утверждения и действия со ссылкой (только у загруженной памятки).
class _LeafletHead extends StatelessWidget {
  const _LeafletHead({required this.token, required this.leaflet, required this.onCopy, required this.onOpen});

  final String token;
  final PublicLeaflet? leaflet;
  final VoidCallback onCopy;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final language = leaflet?.language ?? '';
    final approvedAt = leaflet?.approvedAt ?? '';
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text([s.leafletNumber(leafletId(token)), if (language.isNotEmpty) language.toUpperCase()].join(' · '), style: theme.textTheme.labelSmall),
          if (approvedAt.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text('${s.myLeafletApprovedOn(dateTimeShort(approvedAt))} · ${s.myLeafletApprovedBy.toLowerCase()}', style: theme.textTheme.bodySmall),
          ],
          if (leaflet != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                OutlinedButton.icon(style: AppButtons.small(context), onPressed: onCopy, icon: const Icon(Icons.link, size: 18), label: Text(s.myCopyLink)),
                OutlinedButton.icon(
                  style: AppButtons.small(context),
                  onPressed: onOpen,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text(s.myOpenInBrowser),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// «О чём вы говорили с врачом» с меткой «черновик ИИ» и оговоркой, что памятка не заменяет консультацию.
class _TalkedNote extends StatelessWidget {
  const _TalkedNote();

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    return AppCard(
      padding: AppCard.plain,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [Text(s.myLeafletTalked, style: theme.textTheme.titleSmall), const OriginTag(Origin.ai)],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(s.myLeafletFooter, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

/// Подвал памятки: аудио удалено, персональных данных нет, данные синтетические.
class _LeafletFooter extends StatelessWidget {
  const _LeafletFooter();

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final style = Theme.of(context).textTheme.labelSmall;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final note in [s.myLeafletAudioDeleted, s.myLeafletNoPersona, s.myLeafletSynthetic])
            Padding(padding: const EdgeInsets.only(bottom: AppSpacing.xs), child: Text(note, style: style)),
        ],
      ),
    );
  }
}
