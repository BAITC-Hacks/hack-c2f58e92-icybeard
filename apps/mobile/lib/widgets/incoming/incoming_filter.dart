import 'package:flutter/foundation.dart';

import '../../api/models.dart';

/// Этап входящего направления — только для фильтра списка, как `stageOf` веба (`IncomingReferralsView.vue`):
/// выписан или закрыт → [closed]; госпитализирован → [admitted]; приём подтверждён → [scheduled]; пациент
/// согласился → [confirm] (ждут нашего подтверждения); иначе → [consent] (ждём согласия пациента). Кнопки этим не
/// управляются: они берутся только из `item.allowed`.
enum IncomingStage { consent, confirm, scheduled, admitted, closed }

/// Этап строки для фильтра; незнакомый статус нового сервера не ломает разбор — решают флаги согласия и подтверждения.
IncomingStage incomingStageOf(IncomingReferral item) {
  if (item.discharged || item.closedReason != null || item.status == RouteCodes.statusClosed) {
    return IncomingStage.closed;
  }
  if (item.admitted || item.status == RouteCodes.statusAdmitted) {
    return IncomingStage.admitted;
  }
  if (item.confirmed) {
    return IncomingStage.scheduled;
  }
  return item.patientConsent == RouteCodes.consentAccepted ? IncomingStage.confirm : IncomingStage.consent;
}

/// Сколько строк на каждом этапе — числа в листе выбора этапа («Дата назначена · 2»); этап без строк — 0.
Map<IncomingStage, int> incomingStageCounts(List<IncomingReferral> items) {
  final counts = {for (final stage in IncomingStage.values) stage: 0};
  for (final item in items) {
    final stage = incomingStageOf(item);
    counts[stage] = counts[stage]! + 1;
  }
  return Map.unmodifiable(counts);
}

/// Сколько тяжёлых случаев — число у переключателя «Только тяжёлые».
int incomingSevereCount(List<IncomingReferral> items) => items.where((i) => i.severe).length;

/// Отбор списка входящих на телефоне (веб фильтрует уже загруженный список так же): этап (null — все), только
/// тяжёлые и поиск по рефу, отправителю (имя и код) и профилю койки. Неизменяемый: каждое изменение — новый фильтр.
@immutable
class IncomingFilter {
  const IncomingFilter({this.stage, this.severeOnly = false, this.query = ''});

  /// Без отбора: показано всё в серверном порядке.
  static const none = IncomingFilter();

  final IncomingStage? stage;
  final bool severeOnly;
  final String query;

  /// Сужает ли фильтр список: пустой поиск (одни пробелы) фильтром не считается.
  bool get isActive => stage != null || severeOnly || query.trim().isNotEmpty;

  /// Тот же фильтр с другим этапом; null — все этапы.
  IncomingFilter withStage(IncomingStage? value) => IncomingFilter(stage: value, severeOnly: severeOnly, query: query);

  IncomingFilter withSevereOnly(bool value) => IncomingFilter(stage: stage, severeOnly: value, query: query);

  IncomingFilter withQuery(String value) => IncomingFilter(stage: stage, severeOnly: severeOnly, query: value);

  /// Подходит ли строка; [profileName] — название профиля койки (без справочника — пусто, ищется по коду).
  bool matches(IncomingReferral item, {String profileName = ''}) {
    if (stage != null && incomingStageOf(item) != stage) {
      return false;
    }
    if (severeOnly && !item.severe) {
      return false;
    }
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return true;
    }
    final haystack = [item.patientRef, item.fromMoName, item.fromMoCode, item.profileCode, profileName].join(' ').toLowerCase();
    return haystack.contains(needle);
  }
}

/// Строки, подходящие под [filter], в серверном порядке (тяжёлые первыми, затем новые) — новый список, исходный не
/// меняется. [profileNames] — код профиля койки → название (справочник `GET /refdata/profiles`).
List<IncomingReferral> applyIncomingFilter(List<IncomingReferral> items, IncomingFilter filter, Map<String, String> profileNames) => [
      for (final item in items)
        if (filter.matches(item, profileName: profileNames[item.profileCode] ?? '')) item,
    ];

/// Порядок кнопок карточки, как в таблице веба: «Подтвердить приём», «Отказать», «Госпитализирован», «Выписать»,
/// «Перенести», «Не пришёл». `close` — не кнопка карточки: маршрут снимают с листа ожидания на странице пациента (Q-18).
const incomingActionOrder = [
  RouteCodes.actionConfirm,
  RouteCodes.actionReject,
  RouteCodes.actionAdmit,
  RouteCodes.actionDischarge,
  RouteCodes.actionReschedule,
  RouteCodes.actionNoShow,
];

/// Кнопки карточки — только те коды, что сервер перечислил в `item.allowed`, в порядке [incomingActionOrder];
/// незнакомые коды не показываются.
List<String> incomingActions(IncomingReferral item) => [
      for (final action in incomingActionOrder)
        if (item.can(action)) action,
    ];
