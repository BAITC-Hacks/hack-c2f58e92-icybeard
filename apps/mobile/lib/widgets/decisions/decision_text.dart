import 'package:flutter/foundation.dart';

import '../../api/models.dart';
import '../../l10n/strings.dart';
import '../format.dart';

// Тексты журнала решений — порт lib/decision.ts и DecisionsView.vue веба: какие записи показывать, объект решения
// словами, что произошло (события маршрута — подписями журнала в голосе персонала, решение Q-8), рекомендация и
// выбор короткими именами. Чистые функции: ни сырого JSON, ни номера записи.

/// Справочники для подписей: регион по КАТО, профиль койки и организация по коду; незнакомый код — сам код.
@immutable
class DecisionNames {
  const DecisionNames({this.regions = const {}, this.profiles = const {}, this.organizations = const {}});

  final Map<String, String> regions;
  final Map<String, String> profiles;
  final Map<String, String> organizations;

  String region(String kato) => regions[kato] ?? kato;
  String profile(String code) => profiles[code] ?? code;

  /// Полное юридическое имя организации или код.
  String organization(String code) => organizations[code] ?? code;

  /// Короткое имя организации (`shortOrgName`) или код.
  String short(String code) => shortOrgName(organization(code));
}

/// Записи для журнала: служебные события записи приёма (`subject: scribe` — запрос согласия, сессия, памятка) — не
/// решения врача, их видно в скрайбе и у пациента (решение API 13). Порядок сервера, новый список.
List<DecisionRecord> journalDecisions(List<DecisionRecord> all) => [
      for (final d in all)
        if (d.subject != DecisionCodes.subjectScribe) d,
    ];

/// Объект решения словами (`describeSubject` веба): новое направление — «регион · профиль · дата» из subjectId
/// `регион.организация.профиль.дата`; сигнал по данным — «сигнал {8 знаков id}»; пациент в очереди — реф.
String decisionObject(S s, DecisionRecord d, DecisionNames names) {
  final id = d.subjectId ?? '';
  if (d.subject == DecisionCodes.subjectReferral) {
    final parts = id.split('.');
    if (parts.length >= 4 && parts[0].isNotEmpty && parts[2].isNotEmpty && parts[3].isNotEmpty) {
      return '${names.region(parts[0])} · ${names.profile(parts[2])} · ${parts[3]}';
    }
  }
  if (d.subject == DecisionCodes.subjectAnomaly) {
    return s.decisionsAnomaly(id.length > 8 ? id.substring(0, 8) : id);
  }
  return id;
}

/// Что произошло — строка под объектом. События маршрута (`DecisionRecord.event` из 17 видов журнала) — подпись
/// журнала врача с коротким именем больницы из `chosen.moCode` («Предложен перевод: Достар Мед», «Достар Мед: приём
/// подтверждён»); снятие с листа — ещё и причина («Снят по просьбе пациента»). Решение про организацию —
/// «рекомендовано → выбрано», если выбрано иначе, иначе выбранная. Нечего сказать — null.
String? decisionWhat(S s, DecisionRecord d, DecisionNames names) {
  final event = d.event;
  final chosen = d.chosenMoCode;
  if (RouteCodes.journalKinds.contains(event)) {
    final title = s.routeJournalTitle(event, RouteVoice.staff, name: chosen == null ? '' : names.short(chosen));
    final closes = _text(d.chosen, 'closes');
    return event == RouteCodes.journalClose && closes != null ? '$title · ${s.routeClosedReason(closes, RouteVoice.staff)}' : title;
  }
  if (chosen == null) return null;
  final recommended = d.recommendedMoCode;
  return d.outcome == DecisionCodes.outcomeDiffer && recommended != null ? '${names.short(recommended)} → ${names.short(chosen)}' : names.short(chosen);
}

/// «Дата госпитализации: дд.мм.гггг» для подтверждения и переноса (`chosen.plannedAt`); иначе null.
String? decisionPlanned(S s, DecisionRecord d) {
  final planned = _text(d.chosen, 'plannedAt');
  return planned == null ? null : s.routeJournalPlanned(routeDate(planned));
}

/// «Рекомендовано» в подробностях: короткое имя рекомендованной организации; без рекомендации — «—».
String decisionRecommended(DecisionRecord d, DecisionNames names) {
  final code = d.recommendedMoCode;
  return d.outcome == DecisionCodes.outcomeNone || code == null ? '—' : names.short(code);
}

/// «Выбрано» в подробностях: короткое имя выбранной организации; у события маршрута без организации (отмена,
/// снятие) — его подпись; иначе «—».
String decisionChosen(S s, DecisionRecord d, DecisionNames names) {
  final code = d.chosenMoCode;
  if (code != null) return names.short(code);
  return RouteCodes.journalKinds.contains(d.event) ? decisionWhat(s, d, names) ?? '—' : '—';
}

String? _text(Map<String, dynamic>? map, String key) {
  final value = map?[key];
  return value is String && value.isNotEmpty ? value : null;
}
