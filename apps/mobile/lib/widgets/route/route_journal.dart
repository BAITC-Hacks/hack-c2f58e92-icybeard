import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../../theme/tokens.dart';
import '../../theme/tones.dart';
import '../../theme/typography.dart';
import '../format.dart';
import '../org_name.dart';

/// Тон точки записи журнала (RouteFeed.vue): свои записи гражданина — signal (warn), решения «за» пациента
/// (keep, confirm, admit, discharge) — keep (ok), отказ, отмена и неявка — stop (нейтральный), остальное — redirect
/// (accent-subtle).
enum JournalTone { signal, keep, stop, redirect }

/// Тон точки по виду записи; незнакомый вид — redirect, как в вебе.
JournalTone journalToneOf(String kind) {
  if (routeJournalByCitizen(kind)) {
    return JournalTone.signal;
  }
  return switch (kind) {
    'reject' || 'cancel' || 'no_show' => JournalTone.stop,
    'keep' || 'confirm' || 'admit' || 'discharge' => JournalTone.keep,
    _ => JournalTone.redirect,
  };
}

/// Значок в точке по виду записи — Material-аналоги иконок веба; незнакомый вид и записи-комментарии — облачко.
IconData journalIconOf(String kind) => switch (kind) {
      'redirect' => Icons.swap_horiz,
      'keep' => Icons.check,
      'confirm' || 'reschedule' => Icons.event,
      'admit' => Icons.apartment,
      'discharge' => Icons.logout,
      'reject' || 'cancel' || 'no_show' => Icons.close,
      'close' => Icons.flag_outlined,
      'consent_accepted' => Icons.thumb_up_outlined,
      'consent_declined' => Icons.thumb_down_outlined,
      _ => Icons.chat_bubble_outline,
    };

/// Момент записи «дд.мм.гггг, чч:мм» по часам устройства — как `dateTime` веба. Дата и время берутся из одного
/// местного момента; пустая строка — «—», неразборчивая — как есть.
String journalMoment(String iso) {
  final parsed = DateTime.tryParse(iso);
  if (parsed == null) {
    return iso.isEmpty ? '—' : iso;
  }
  final local = parsed.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(local.day)}.${two(local.month)}.${local.year}, ${two(local.hour)}:${two(local.minute)}';
}

/// Лента журнала маршрута («Решения и запросы») — `PatientRoute.journal` в серверном порядке (свежие первыми), без
/// пересортировки. [voice] выбирает формулировки: гражданину — во втором лице («Вы попросили…», «кто» — «вы»),
/// персоналу — в третьем («Пациент просит…», «пациент») с отметкой тяжёлого случая. Пустая лента — «Решений пока
/// нет.». Заголовок раздела (`routeJournalHeading`), карточка и прокрутка — у экрана.
class RouteJournal extends StatelessWidget {
  const RouteJournal({super.key, required this.entries, required this.voice});

  final List<RouteJournalEntry> entries;
  final RouteVoice voice;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      final theme = Theme.of(context);
      return Text(S.at(context).routeJournalEmpty, style: theme.textTheme.bodyMedium?.copyWith(color: AppPalette.of(context).muted));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final (i, entry) in entries.indexed) RouteJournalRow(entry: entry, voice: voice, last: i == entries.length - 1)],
    );
  }
}

/// Строка ленты (RouteFeed.vue): слева точка 30 с тоном и значком по виду; справа заголовок по голосу с коротким
/// именем больницы (тап по нему открывает полное юридическое имя), строка «дд.мм.гггг, чч:мм · кто» (персоналу ещё
/// « · тяжёлый случай»), «Дата госпитализации: …» при `plannedAt` и плашка с причиной или комментарием при `reason`.
/// Разделитель border-soft снизу, кроме [last].
class RouteJournalRow extends StatelessWidget {
  const RouteJournalRow({super.key, required this.entry, required this.voice, this.last = false});

  final RouteJournalEntry entry;
  final RouteVoice voice;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final reason = entry.reason;
    final planned = entry.plannedAt;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: last ? null : BoxDecoration(border: Border(bottom: BorderSide(color: colors.borderSoft))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _JournalDot(kind: entry.kind),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _JournalTitle(entry: entry, voice: voice),
                const SizedBox(height: 2),
                _JournalMeta(entry: entry, voice: voice),
                if (planned != null && planned.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(s.routeJournalPlanned(dateShort(planned)), style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600).merge(AppType.numeric)),
                  ),
                if (reason != null && reason.isNotEmpty) _JournalNote(label: s.routeJournalNoteLabel(entry.kind, voice), text: reason),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JournalDot extends StatelessWidget {
  const _JournalDot({required this.kind});

  final String kind;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final tones = AppTones.of(context);
    final tone = switch (journalToneOf(kind)) {
      JournalTone.signal => tones.warn,
      JournalTone.keep => tones.ok,
      JournalTone.stop => Tone(colors.muted, colors.neutralSoft),
      JournalTone.redirect => Tone(colors.accentHover, colors.accentSubtle),
    };
    // ключ — опора для тестов цвета точки; виды в разных строках не конфликтуют
    return SizedBox.square(
      key: ValueKey('journal-dot-$kind'),
      dimension: AppSizes.feedDot,
      child: ExcludeSemantics(
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: tone.bg),
          child: Icon(journalIconOf(kind), size: 15, color: tone.fg),
        ),
      ),
    );
  }
}

/// Заголовок записи: шаблон словаря с коротким именем больницы; если имя сокращено, оно подчёркнуто пунктиром и
/// тап открывает лист с полным юридическим именем (как OrgName).
class _JournalTitle extends StatelessWidget {
  const _JournalTitle({required this.entry, required this.voice});

  final RouteJournalEntry entry;
  final RouteVoice voice;

  static const _marker = '\u0000';

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final style = theme.textTheme.row;
    final full = (entry.moName ?? '').trim();
    final short = shortOrgName(full);
    final title = s.routeJournalTitle(entry.kind, voice, name: short);
    final parts = s.routeJournalTitle(entry.kind, voice, name: _marker).split(_marker);
    if (full.isEmpty || short == full || parts.length != 2) {
      return Text(title, style: style);
    }
    return Semantics(
      button: true,
      label: '$title. ${s.fullNameHint}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => showOrgNameSheet(context, full),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(text: parts.first),
              TextSpan(
                text: short,
                style: TextStyle(decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted, decorationColor: AppPalette.of(context).faint),
              ),
              TextSpan(text: parts.last),
            ],
          ),
          style: style,
        ),
      ),
    );
  }
}

/// «дд.мм.гггг, чч:мм · кто» мелко text-secondary; персоналу при `severe` — « · тяжёлый случай» красным.
class _JournalMeta extends StatelessWidget {
  const _JournalMeta({required this.entry, required this.voice});

  final RouteJournalEntry entry;
  final RouteVoice voice;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final who = s.routeJournalWho(entry.kind, entry.role, voice);
    final meta = [journalMoment(entry.at), if (who.isNotEmpty) who].join(' · ');
    final severe = voice == RouteVoice.staff && entry.severe;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: meta),
          if (severe) ...[
            const TextSpan(text: ' · '),
            TextSpan(text: s.routeSevereMark, style: TextStyle(color: AppTones.of(context).danger.fg, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
      style: theme.textTheme.rowDetail.copyWith(color: colors.muted).merge(AppType.numeric),
    );
  }
}

/// Плашка с причиной решения или комментарием: surface-muted, radius 10, сверху мелкая жирная подпись.
class _JournalNote extends StatelessWidget {
  const _JournalNote({required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(color: colors.neutralSoft, borderRadius: BorderRadius.circular(AppRadius.plate)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.caption.copyWith(fontWeight: FontWeight.w700, color: colors.muted)),
          const SizedBox(height: 2),
          Text(text, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
